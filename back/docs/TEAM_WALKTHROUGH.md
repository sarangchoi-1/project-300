# Backend 1 — team walkthrough

A script for explaining the auth foundation to the team. Roughly 15 minutes if you
talk through it in order. Sections 6 and 7 are the ones your teammates actually
need; section 8 is what we have to decide together today.

Reference docs, for afterwards:
[schema and rules](./BACKEND1_HANDOFF.md) ·
[Flutter calls](./FLUTTER_AUTH_INTEGRATION.md) ·
[Backend 2 contract](./BACKEND2_RLS_CONTRACT.md) ·
[한국어 버전](./TEAM_WALKTHROUGH.ko.md)

---

## 1. Where we are

Login, signup, user approval, profiles, groups, group roles, and all the
permission rules are **done and tested**. It runs locally. Nothing is deployed to
a real cloud project yet, and the Flutter app hasn't started.

On branch `sarang`: 6 SQL migration files, 2 test suites, 3 reference docs.

---

## 2. The one thing everyone has to understand

There is **no backend server** in this project. We are not writing Java or Node.

Normally it goes: **app → your server → database.** The server is the bouncer; it
decides who's allowed to see what.

With Supabase it goes: **app → database.** The Flutter app talks to the database
almost directly over HTTP.

So the bouncer has to move *into* the database. Every permission rule is written in
SQL and enforced by PostgreSQL itself, using a feature called **Row Level
Security** (RLS).

> **Say this part out loud to the team:** because there is no server of ours in the
> middle, those SQL rules are the *only* thing between a stranger and our data.
> Anyone can extract our app's API key from the installed app — that's normal and
> expected. It's safe only because every table has RLS turned on. A new table
> without RLS is a publicly readable table.

That's why Backend 2 has a contract to follow rather than a free hand.

---

## 3. What was built

Three tables.

**`profiles`** — one row per user, created **automatically** the instant someone
signs up. Holds their `display_name`, their `role`, and their `approval_status`.
Passwords are not here; Supabase Auth keeps those, hashed, in its own table.

**`groups`** — the small groups / cells. Name and description.

**`group_members`** — who is in which group, and whether they're a `member` or the
`leader` of it.

Two ideas control everything:

**Role** — `member`, `leader`, or `admin`. What you're allowed to *do*.

**Approval status** — `pending`, `approved`, or `rejected`. Whether you can see
*anything at all*. Everyone starts as `pending`.

These are independent on purpose. An unapproved admin has no power; an approved
member has normal access.

A few rules are enforced by the database itself, not by app code, so they can't be
bypassed by a bug in Flutter:

- A user can be in **only one active group** at a time.
- The same user can't be added to the same group twice.
- Two groups can't have the same name.
- Group leadership is stored in exactly one place, so it can't disagree with itself.

---

## 4. Who can see what

Reading access:

| | Not signed in | Pending | Member | Leader | Admin |
|---|---|---|---|---|---|
| `profiles` | nothing | own row | own row | own row | everyone |
| `groups` | nothing | nothing | own group | own group | all |
| `group_members` | nothing | nothing | own row | **whole roster** | all |

Writing access is simpler: **only admins can write anything.** Nobody can join a
group, leave a group, promote themselves, approve themselves, rename a group, or
change anyone's role. Leaders can *read* their roster but not change it.

This comes from 14 policies, and the test suite checks every cell of that table.

---

## 5. What a user's life looks like

Agree on this flow as a team, because the Flutter screens depend on it.

1. Someone downloads the app and signs up with email, password, and a display name.
2. A profile is created automatically: role `member`, status `pending`.
3. They are logged in — but they see a **"waiting for approval"** screen, not the app.
   If they poke at the data, they get empty lists, not errors.
4. An admin sees them in a pending list and approves them.
5. Next time they open the app, they're in. The session is saved on the phone, so
   there's no login screen — it auto-logs in.
6. An admin puts them in a group, and optionally makes them that group's leader.

Note step 3: a pending user *can* read their own profile. That's deliberate — it's
how the app knows to show the waiting screen.

---

## 6. Flutter developer — what you need to know

Everything you need is in
[FLUTTER_AUTH_INTEGRATION.md](./FLUTTER_AUTH_INTEGRATION.md) with copy-pasteable
code. The five things to hear now:

**Use the `supabase_flutter` package.** No HTTP client, no custom API layer. You
call `supabase.from('profiles').select()` and that's the API.

**Don't create the profile yourself.** Just call
`signUp(email:, password:, data: {'display_name': ...})`. The database makes the
profile row. You have no permission to insert one anyway.

**Auto-login is free.** After `Supabase.initialize()`, read
`supabase.auth.currentSession`. If it's non-null, they're already logged in. If it's
null, show the sign-in screen.

**Gate the whole app on `approval_status`.** Fetch the profile after login and
branch: `pending` → waiting screen, `rejected` → denied screen, `approved` → the
real app. On the waiting screen, an empty list is the *correct* answer, not an error.

**The one trap that will cost you a day.** If RLS blocks an update, you do **not**
get an error. You get HTTP 200 and an empty array — identical to success. So always
chain `.select()` onto an update or delete and check you actually got a row back:

```dart
final rows = await supabase.from('profiles')
    .update({'approval_status': 'approved'})
    .eq('id', userId)
    .select();

if (rows.isEmpty) {
  // not an error — you simply were not allowed
}
```

---

## 7. Backend 2 — what you need to know

Full version in [BACKEND2_RLS_CONTRACT.md](./BACKEND2_RLS_CONTRACT.md), including
complete worked policies for `attendance` and `prayer_requests` you can adapt.

You own `bulletins`, `meetings`, `attendance`, `prayer_requests`, PDF storage, and
notifications. I own identity, groups, and permissions. The interface between us is
a set of **helper functions**. Use them instead of writing your own joins against
`profiles` or `group_members`:

- `is_approved()` — put this in **every** read policy, so pending users see nothing
- `is_admin()`
- `is_group_member(group_id)` — for group-scoped tables like `meetings`
- `is_group_leader(group_id)`
- `is_group_leader_of_user(user_id)` — for user-scoped tables like `attendance`

Why not just write the join yourself? Because if we later change the membership
model, every policy built on these helpers keeps working, and every hand-written
join silently breaks.

Four non-negotiables:

1. `enable row level security` on every table you expose. No exceptions.
2. **Never** use `force row level security`. Our helpers depend on the owner
   bypassing RLS; forcing it causes infinite recursion and breaks every policy in
   the database.
3. Write `to authenticated` on every policy. Omitting it silently includes
   anonymous users.
4. Point user foreign keys at `public.profiles(id)`, not `auth.users(id)`.

Add your cases to `back/supabase/tests/` when you're done — a member, a leader of a
*different* group, a pending user, and an anonymous caller all have to be denied.

---

## 8. Decisions we need today

**a) Can group leaders see their members' names?** Right now: no. A leader sees the
roster rows in `group_members` but only their own row in `profiles` — so an
attendance screen would show user IDs with no names. I built it narrow on purpose
and left the call to the team. *Recommendation: yes, open it up.* It's a one-policy
change and Backend 2's attendance screen needs it.

**b) Can members edit their own display name?** Right now: no, nobody can edit their
own profile at all. Deliberately locked until someone asks for it. *Recommendation:
allow display name only*, nothing else.

**c) Do we require email confirmation on signup?** Right now: off. Our admin
approval already blocks strangers, so confirmation mainly stops typo'd or
someone-else's email addresses. It does change the Flutter flow — with it on,
`signUp` returns no session until they click the link. *Recommendation: leave it off
for the MVP.*

**d) Who is the first admin, and when do we deploy?** Nothing is in the cloud yet.
Deploying needs one person's approval, and the first admin has to sign up in the app
before they can be promoted.

---

## 9. Running it yourself

You need Docker running. Then:

```bash
cd back
supabase start          # first run downloads ~15 GB of images
supabase db reset       # builds the database from the 6 migration files
```

Useful addresses once it's up:

- Supabase Studio (browse tables, run SQL): `http://127.0.0.1:54323`
- API the Flutter app talks to: `http://127.0.0.1:54321`
- Captured emails: `http://127.0.0.1:54324`
- `cd back && supabase status` prints the keys to put in the Flutter app

To check nothing is broken after a change:

```bash
back/scripts/verify-local.sh    # ~1 second, no Docker needed
back/scripts/verify-e2e.sh      # needs the stack up; tests over real HTTP
```

The first runs 10 sections of SQL tests. The second runs 27 checks through real
signup, real login tokens, and the real API — including confirming that a member
genuinely cannot make themselves an admin.

---

## 10. Where things are

```
back/supabase/migrations/     the 6 files that build the database, run in order
back/supabase/tests/          the test suites
back/scripts/                 the two verification runners
back/docs/                    reference documentation
.env.example                  names of the environment variables (no real values)
```

Read the migrations in filename order and you're reading the system being built:
types, then tables, then helper functions, then the permission rules, then the
admin bootstrap.

Never edit a migration that has already run — add a new file with a later
timestamp instead.

---

## 11. Words that will come up

**RLS (Row Level Security)** — PostgreSQL deciding, per row, whether you're allowed
to see or change it. Our entire permission system.

**Policy** — one RLS rule. We have 14.

**`auth.uid()`** — inside SQL, "the ID of whoever is making this request." Comes
from the signed login token and can't be faked.

**anon key** — the public API key shipped inside the app. Public by design; safe
only because RLS is on.

**service role key** — the master key that bypasses all rules. Server-side only.
Never in the Flutter app, never committed. We don't currently use it anywhere.

**Migration** — a numbered SQL file that builds part of the database. Runs once,
tracked by the database.

**PostgREST** — the Supabase piece that turns our tables into the HTTP API
automatically. Why we don't write endpoints.

**Supabase Auth** — the piece that handles signup, login, and passwords, and owns
the `auth.users` table.
