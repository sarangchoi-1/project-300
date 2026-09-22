# Backend 1 — Identity, Organization, Authorization

The secure Supabase foundation that everything else sits on: email/password auth,
admin approval, profiles, groups, group membership, roles, and the authorization
helpers that Backend 2 must reuse.

There is no application server. Supabase Auth issues the JWT, PostgREST exposes
the tables, and PostgreSQL Row Level Security is the only authorization layer.

Companion documents:

- [`FLUTTER_AUTH_INTEGRATION.md`](./FLUTTER_AUTH_INTEGRATION.md) — exact client calls
- [`BACKEND2_RLS_CONTRACT.md`](./BACKEND2_RLS_CONTRACT.md) — how to write feature RLS

---

## 1. Schema overview

```
auth.users (Supabase-managed, holds the password hash)
   │ 1:1, ON DELETE CASCADE
   ▼
public.profiles ── display_name, role, approval_status
   │ 1:N, ON DELETE CASCADE
   ▼
public.group_members ── role (member|leader), is_active
   │ N:1, ON DELETE CASCADE
   ▼
public.groups ── name, description, is_active
```

`public.groups` has **no** outbound foreign key. Leadership lives on
`group_members.role`, so the graph is acyclic and there is exactly one source of
truth for "who leads group X".

### Enum types

| Type | Values |
| --- | --- |
| `public.app_role` | `member`, `leader`, `admin` |
| `public.approval_status` | `pending`, `approved`, `rejected` |
| `public.group_role` | `member`, `leader` |

### `public.profiles`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` PK | = `auth.users.id` = `auth.uid()`, cascade delete |
| `display_name` | `text` not null | 1–60 characters after trimming |
| `role` | `app_role` | default `member`, admin-writable only |
| `approval_status` | `approval_status` | default `pending`, admin-writable only |
| `created_at` / `updated_at` | `timestamptz` | `updated_at` is trigger-maintained |

Indexed on `approval_status` and `role` for the admin console.

Passwords exist only in `auth.users`, hashed by Supabase Auth. Nothing in this
schema reads, copies, or mirrors credential data.

### `public.groups`

`id`, `name`, `description`, `is_active`, timestamps. Names are unique
case-insensitively (`lower(btrim(name))`), so "Group A" cannot be created twice.

### `public.group_members`

`id`, `group_id`, `user_id`, `role`, `is_active`, `joined_at`, timestamps.

Two constraints encode the membership rules:

- `unique (group_id, user_id)` — a user appears at most once per group.
- a partial unique index on `(user_id) where is_active` — **a user belongs to at
  most one _active_ group.** Inactive rows are unlimited, so group history is
  preserved for Backend 2's attendance features.

To move someone between groups: set the old row `is_active = false`, then insert
the new row. To support multi-group membership later, drop
`group_members_one_active_group_per_user_idx` and update this document.

---

## 2. Role and approval rules

Two independent axes. **Approval controls whether you see anything at all; role
controls what you can do once approved.**

| Role | Meaning |
| --- | --- |
| `member` | Ordinary user. Read-only on their own data. |
| `leader` | App-wide label. Real authority comes from `group_members.role = 'leader'`. |
| `admin` | Approves users, assigns roles, manages groups and membership. |

| Approval status | Effect |
| --- | --- |
| `pending` | Can authenticate and read their own profile. Sees no groups, no memberships, no feature data. This is the "waiting for approval" state. |
| `approved` | Full access for their role. |
| `rejected` | Same visibility as `pending`. Retained so the app can explain the state and an admin can reverse it. |

`is_admin()` requires `role = 'admin'` **and** `approval_status = 'approved'`, so
un-approving an admin immediately removes their power.

### Access matrix

| Table | `anon` | pending / rejected | approved member | group leader | admin |
| --- | --- | --- | --- | --- | --- |
| `profiles` | nothing | read own row | read own row | read own row | read **all**, update `display_name` / `role` / `approval_status` on all |
| `groups` | nothing | nothing | read own group | read own group | full CRUD |
| `group_members` | nothing | nothing | read own membership row | read **the whole roster of their group** | full CRUD |

Deliberate omissions, each one a "no" that would otherwise be a vulnerability:

- **No self-service update policy on `profiles` at all.** There is no approved
  profile-editing requirement yet, so a member cannot even change their own
  `display_name`. Adding that later means adding one narrow `profiles_update_own`
  policy — see §6.
- **No client `INSERT` or `DELETE` on `profiles`.** Rows are created by the signup
  trigger; an insert without a matching `auth.users` row would violate the FK, and
  deleting a profile would leave a user who can log in with no profile. Deactivate
  with `approval_status = 'rejected'`; hard-delete via the Auth Admin API, which
  cascades.
- **No non-admin writes to `group_members`.** A member cannot join a group, leave a
  group, or promote themselves to leader. Leaders are read-only on their roster.
- **`group_members.group_id` and `user_id` are not updatable by anyone.** Rewriting
  a membership in place would silently corrupt history; admins delete and re-insert.
- **`anon` holds no privilege on any of these tables**, so an unauthenticated
  request fails at the grant layer before RLS is even consulted.

---

## 3. Authorization helpers

Defined in `20260914120300_auth_foundation_authz_helpers.sql`. All are
`security definer`, `stable`, pinned to `search_path = ''`, and executable only by
`authenticated` and `service_role`.

| Function | Returns |
| --- | --- |
| `public.is_admin()` | caller is an approved admin |
| `public.is_approved()` | caller's profile is `approved` |
| `public.is_group_member(uuid)` | caller has an active membership in that group and is approved |
| `public.is_group_leader(uuid)` | caller is the active, approved leader of that group |
| `public.is_group_leader_of_user(uuid)` | caller leads the active group that this user belongs to |
| `public.active_group_id()` | caller's single active group id, or `null` |
| `public.current_app_role()` | caller's `app_role`, or `null` |

They return `false` / `null` for anonymous callers rather than raising.

**Why `security definer`:** RLS on `profiles` has to ask "is the caller an admin?",
which means reading `profiles` from inside a policy on `profiles`. Done directly
that is infinite recursion. A `security definer` function owned by the table owner
reads the row without re-entering RLS, breaking the cycle.

**Therefore: never enable `force row level security`** on `profiles` or
`group_members`. `FORCE` applies RLS to the table owner too, which reintroduces the
recursion and breaks every policy. A structural test asserts this stays off.

---

## 4. Initial admin bootstrap

`public.bootstrap_first_admin(p_email text)` promotes the first admin. Three
independent locks:

1. `EXECUTE` is revoked from `public`, `anon`, `authenticated`, **and**
   `service_role`. It is not reachable from the Flutter app or from `/rpc`.
2. It raises if any admin already exists, so it cannot be replayed to escalate.
3. It requires that the target has already signed up. It never creates users and
   never touches credentials.

### Steps

1. The person who will be admin signs up in the app normally. They will land on
   the waiting-for-approval screen — expected.
2. Open **Supabase dashboard → SQL Editor** (it runs as the database owner) and run:

   ```sql
   select * from public.bootstrap_first_admin('the-admin@your-church.example');
   ```

   It returns one row with `role = admin` and `approval_status = approved`.
3. That person signs out and back in, and now has the admin view.
4. Every later admin is promoted by an existing admin — from the app, or with:

   ```sql
   update public.profiles set role = 'admin', approval_status = 'approved'
    where id = '<uuid>';
   ```

Re-running step 2 fails on purpose. No key, password, or secret is involved at any
point.

---

## 5. Environment variables

Names only — real values live in an untracked `.env` (see `.env.example`).

| Variable | Where | Secret? |
| --- | --- | --- |
| `SUPABASE_URL` | Flutter app, CI | No |
| `SUPABASE_ANON_KEY` | Flutter app, CI | No — public by design, safe only because RLS is on |
| `SUPABASE_PROJECT_REF` | developer / CI tooling | No |
| `SUPABASE_ACCESS_TOKEN` | Supabase CLI in CI | **Yes** |
| `SUPABASE_DB_PASSWORD` | `supabase db push` / `link` | **Yes** |
| `SUPABASE_SERVICE_ROLE_KEY` | server-side only, if ever needed | **Yes — bypasses RLS entirely** |

The service-role key must never appear in the Flutter app, a migration, a
document, or any committed file. Nothing in this repository references it.

Newer Supabase projects issue `sb_publishable_...` / `sb_secret_...` keys instead
of `anon` / `service_role` JWTs. Either works; keep the variable naming consistent
between the Flutter code and CI.

---

## 6. Open decisions (need your call)

1. **Leaders cannot read their members' profiles.** A leader sees the roster rows
   in `group_members` but only their own row in `profiles`, so an attendance
   screen would show user ids and no names. The literal spec said "leaders can
   view membership records", so I did not widen it. When you want it, the fix is
   one policy:

   ```sql
   create policy profiles_select_group_leader on public.profiles
     for select to authenticated
     using (public.is_group_leader_of_user(id));
   ```

   This is very likely needed before Backend 2's attendance UI ships.
2. **Members cannot edit their own `display_name`** (no self-update policy, per the
   "keep profile editing deliberately narrow" instruction). When approved:

   ```sql
   create policy profiles_update_own on public.profiles
     for update to authenticated
     using (id = (select auth.uid()))
     with check (id = (select auth.uid()));
   ```

   Safe to add: `enforce_profile_privilege_guard` already blocks `role` and
   `approval_status` changes from client roles, and there is a test proving it.
   You would also want to revoke the `role` / `approval_status` column update
   grants' reachability by tightening the grant to `update (display_name)` plus
   admin-only RPCs, if you want belt-and-braces.
3. **Email confirmation is off** in `config.toml`. The approval gate already blocks
   unapproved users, but confirmation would stop signups on typo'd or someone
   else's address. Your call; it changes the Flutter flow (`signUp` returns a null
   session when confirmation is required).
4. **Rejected users keep an active `auth.users` row** and can still sign in to see
   the rejection. If you want a hard block, disable the auth user via the Auth
   Admin API — that is a server-side operation and out of Backend 1's scope.
5. **`app_role = 'leader'` is currently decorative.** Real authority is
   `group_members.role`. Keeping both lets the app show a "Leader" badge without a
   join, but the two can drift. Either accept it as a display hint or drop
   `'leader'` from `app_role`.

---

## 7. Manual setup steps

Nothing has been applied to any cloud project, and no cloud resources were
created. When you are ready:

```bash
# 1. Install the CLI. Homebrew currently fails on this machine because the
#    Command Line Tools ship no macOS 26 SDK, so install the static binary
#    directly instead (this is the same artefact the Homebrew formula uses):
VERSION=2.117.0
curl -fsSLO "https://github.com/supabase/cli/releases/download/v${VERSION}/supabase_${VERSION}_darwin_arm64.tar.gz"
curl -fsSLO "https://github.com/supabase/cli/releases/download/v${VERSION}/checksums.txt"
grep "supabase_${VERSION}_darwin_arm64.tar.gz" checksums.txt | shasum -a 256 -c -
tar -xzf "supabase_${VERSION}_darwin_arm64.tar.gz"
install -m 0755 supabase "$HOME/.local/bin/supabase"   # already on PATH via ~/.zprofile

# 2. Local stack (needs a Docker runtime running; none was running here)
cd back
supabase start
supabase db reset          # applies every migration from scratch

# 3. Only when you decide to: link and push to the hosted project
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push
```

Then confirm in the dashboard:

- **Database → Tables**: RLS badge is on for `profiles`, `groups`, `group_members`.
- **Authentication → Providers**: Email enabled, "Confirm email" set the way you
  decided in §6.3.
- **Authentication → URL Configuration**: redirect URL matches the Flutter deep
  link in `config.toml`.
- Run the §4 bootstrap.

### Verification without Docker

`back/scripts/verify-local.sh` needs only a local PostgreSQL server. It creates a
scratch database, installs a fake `auth` schema, applies every migration **twice**
(idempotency check), runs the regression suite, and drops the database.

```bash
back/scripts/verify-local.sh
```

To additionally exercise the CLI's own migration runner against any PostgreSQL
database, install the auth shim first and then point `migration up` at it:

```bash
psql -d scratch -f back/supabase/tests/00_local_auth_shim.sql
cd back && supabase migration up --db-url "postgresql://user@127.0.0.1:5432/scratch?sslmode=disable"
```

### End-to-end verification with the real stack

`back/scripts/verify-e2e.sh` runs 27 checks against a running local stack using
**real Supabase Auth over HTTP, real JWTs, and real PostgREST**. It covers what the
psql harness structurally cannot: that the `auth.users` signup trigger fires
correctly when the insert comes from Supabase Auth (running as
`supabase_auth_admin`, not a superuser), that RLS behaves the same through
PostgREST as it does in SQL, and that `bootstrap_first_admin` returns 403 even to
the service-role key.

```bash
cd back && supabase start
supabase db reset            # gives bootstrap_first_admin a virgin database
cd .. && back/scripts/verify-e2e.sh
```

Keys are read from `supabase status` at runtime, so nothing secret is stored in the
script. The bootstrap happy path is only observable on a database with no admin
yet; on re-runs the script detects this, verifies the refusal instead, and says so.

The fixtures in `back/supabase/tests/` are test-only and are never applied to a
Supabase project.

---

## 8. Test checklist

Automated equivalents live in `back/supabase/tests/10_authz_regression.sql`; all
pass. Repeat these by hand against a real project after deploying.

**Unauthenticated**
- [ ] Reading `profiles`, `groups`, or `group_members` without a token fails.
- [ ] Signup and signin still work (they go through Auth, not these tables).

**Pending user** (fresh signup, not yet approved)
- [ ] A profile appears automatically with `role = member`, `approval_status = pending`.
- [ ] Signing up with extra metadata such as `{"role":"admin"}` still produces a plain pending member.
- [ ] The user can read their own profile — the waiting screen depends on it.
- [ ] Groups and memberships return zero rows.
- [ ] `update profiles set approval_status='approved'` affects 0 rows.
- [ ] `update profiles set role='admin'` affects 0 rows.

**Approved member**
- [ ] Sees exactly one group: their own.
- [ ] Sees only their own `group_members` row, not the rest of the roster.
- [ ] Cannot read any other user's profile.
- [ ] Cannot create a group, add a membership, change their group role, or leave their group.

**Group leader**
- [ ] Sees every `group_members` row for their group, and none from other groups.
- [ ] `is_group_leader(own_group)` is true; `is_group_leader(other_group)` is false.
- [ ] Cannot add, remove, or re-role roster members.
- [ ] Cannot approve users or rename the group.
- [ ] (Known gap, §6.1) Cannot read their members' profiles.

**Admin**
- [ ] Reads every profile, group, and membership.
- [ ] Approves and rejects users; promotes and demotes roles.
- [ ] Creates, edits, and deletes groups and memberships.
- [ ] Adding the same user to the same group twice is rejected.
- [ ] Adding a user to a second group while their first membership is active is rejected.
- [ ] Deactivating the old membership then inserting the new one succeeds.

**Bootstrap**
- [ ] `supabase.rpc('bootstrap_first_admin', ...)` from the app fails.
- [ ] Running it in the SQL Editor for an email that never signed up fails.
- [ ] Running it a second time fails.

**Structural**
- [ ] RLS on for all three tables; `FORCE` RLS off.
- [ ] Every `security definer` function pins `search_path`.
- [ ] Deleting an `auth.users` row cascades away the profile and its memberships.

---

## 9. Files

```
.env.example                                  variable names only, no values
.gitignore                                    ignores .env and CLI state
back/supabase/config.toml                     local stack + auth config
back/supabase/migrations/
  20260914120000_auth_foundation_base.sql             enums, set_updated_at()
  20260914120100_auth_foundation_profiles.sql         profiles, signup trigger, backfill
  20260914120200_auth_foundation_groups.sql           groups, group_members, constraints
  20260914120300_auth_foundation_authz_helpers.sql    the authorization contract
  20260914120400_auth_foundation_rls.sql              RLS, grants, privilege guard
  20260914120500_auth_foundation_admin_bootstrap.sql  bootstrap_first_admin()
back/supabase/tests/                          local-only fixtures + regression suite
back/scripts/verify-local.sh                  Docker-free verification runner
back/docs/                                    this document and its companions
```

Every migration is idempotent: `create table if not exists`, `create or replace
function`, `drop policy if exists` before `create policy`, and enum creation
wrapped in a `duplicate_object` handler. `verify-local.sh` applies the whole set
twice to prove it.
