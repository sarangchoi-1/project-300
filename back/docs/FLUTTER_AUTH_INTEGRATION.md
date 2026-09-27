# Flutter integration — auth, approval, profile, group

Exact calls against the Backend 1 schema. Everything goes through
`supabase_flutter`; there is no application server to call.

Schema reference: [`BACKEND1_HANDOFF.md`](./BACKEND1_HANDOFF.md).

---

## Setup

```yaml
# pubspec.yaml
dependencies:
  supabase_flutter: ^2.8.0
```

```dart
// main.dart
Future<void> main() async {
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  runApp(const App());
}

final supabase = Supabase.instance.client;
```

```bash
flutter run \
  --dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

Never add `SUPABASE_SERVICE_ROLE_KEY` to the app — it bypasses RLS completely.

### Against the local stack

`cd back && supabase start`, then `supabase status` prints the values to use.
`API_URL` is `http://127.0.0.1:54321` and `ANON_KEY` / `PUBLISHABLE_KEY` are fixed
demo values that only work locally. Two notes for device testing: an Android
emulator reaches the host at `10.0.2.2` rather than `127.0.0.1`, and signup
confirmation emails are captured by Mailpit at `http://127.0.0.1:54324` instead of
being sent. Supabase Studio is at `http://127.0.0.1:54323`.

---

## 1. Sign up

`display_name` is passed as user metadata. The `on_auth_user_created` trigger reads
**only** that field and forces `role = member`, `approval_status = pending`, so
there is nothing to guard against on the client side and nothing extra to insert.

```dart
final res = await supabase.auth.signUp(
  email: email,
  password: password,
  data: {'display_name': displayName},   // trimmed and truncated to 60 chars server-side
);
```

Do **not** insert into `profiles` after signup — the client has no `INSERT`
privilege and the row already exists.

If email confirmation is enabled in the project, `res.session` is `null` and the
user must confirm before signing in. With confirmation off (the current
`config.toml` default) `res.session` is populated immediately.

---

## 2. Sign in

```dart
await supabase.auth.signInWithPassword(email: email, password: password);
```

---

## 3. Auto-login at startup

`supabase_flutter` persists and refreshes the session automatically. Read it
synchronously after `initialize`:

```dart
final session = supabase.auth.currentSession;   // null => show the auth screen
```

React to changes:

```dart
supabase.auth.onAuthStateChange.listen((data) {
  switch (data.event) {
    case AuthChangeEvent.signedIn:
    case AuthChangeEvent.initialSession:
      // (re)load the profile
      break;
    case AuthChangeEvent.signedOut:
      // clear cached profile state
      break;
    default:
      break;
  }
});
```

---

## 4. Fetch the profile

RLS already limits the result to the caller's own row, but filter explicitly so the
intent is readable:

```dart
final userId = supabase.auth.currentUser!.id;

final row = await supabase
    .from('profiles')
    .select('id, display_name, role, approval_status, created_at')
    .eq('id', userId)
    .maybeSingle();
```

`role` is one of `member` / `leader` / `admin`; `approval_status` is
`pending` / `approved` / `rejected`.

---

## 5. Gate the app on approval

```dart
Widget routeFor(Session? session, Profile? profile) {
  if (session == null)  return const SignInScreen();
  if (profile == null)  return const ProfileLoadErrorScreen();   // should not happen

  switch (profile.approvalStatus) {
    case ApprovalStatus.pending:
      return const WaitingForApprovalScreen();
    case ApprovalStatus.rejected:
      return const AccessDeniedScreen();
    case ApprovalStatus.approved:
      return profile.role == AppRole.admin
          ? const AdminHome()
          : const MemberHome();
  }
}
```

A pending user is fully authenticated — they just cannot see content. Every read
policy on group data requires `is_approved()`, so a pending session gets empty
lists rather than errors. Do not treat an empty list as a failure on the waiting
screen.

To re-check after an admin approves, refetch the profile (pull-to-refresh, or
subscribe to realtime changes on the user's own `profiles` row).

---

## 6. Sign out

```dart
await supabase.auth.signOut();   // clears the persisted session
```

---

## 7. Read the user's own group

One query, using the `group_members → groups` foreign key for the embed. RLS
applies to the embedded table too, so this returns the group only if the user is
genuinely an approved member of it.

```dart
final membership = await supabase
    .from('group_members')
    .select('id, role, is_active, groups(id, name, description)')
    .eq('is_active', true)
    .maybeSingle();          // at most one active group per user, enforced in SQL
```

`membership['role']` is the group-scoped role (`member` / `leader`) — this, not
`profiles.role`, is what decides whether to show leader features.

A plain member sees only their own row here. A group leader sees the whole roster
of their group:

```dart
final roster = await supabase
    .from('group_members')
    .select('user_id, role, is_active, joined_at')
    .eq('group_id', groupId);
```

> Known gap: leaders cannot currently read their members' `profiles` rows, so the
> roster has no display names. See open decision §6.1 in the handoff.

---

## 8. Calling the authorization helpers from the client

Useful for driving UI without duplicating the rules:

```dart
final isAdmin   = await supabase.rpc('is_admin')   as bool;
final isOk      = await supabase.rpc('is_approved') as bool;
final groupId   = await supabase.rpc('active_group_id') as String?;
final isLeader  = await supabase.rpc('is_group_leader',
                        params: {'p_group_id': groupId}) as bool;
```

These are advisory only — the same checks are enforced inside RLS, so a tampered
client gains nothing.

`bootstrap_first_admin` is intentionally **not** callable; `supabase.rpc` on it
returns a permission error.

---

## 9. Admin operations

All of these succeed only for an approved admin; RLS makes them no-ops or errors
for everyone else.

```dart
// Users waiting for approval
final pending = await supabase
    .from('profiles')
    .select('id, display_name, created_at')
    .eq('approval_status', 'pending')
    .order('created_at');

// Approve / reject
await supabase.from('profiles')
    .update({'approval_status': 'approved'}).eq('id', userId).select();

// Change an app-wide role
await supabase.from('profiles')
    .update({'role': 'leader'}).eq('id', userId).select();

// Groups
final group = await supabase.from('groups')
    .insert({'name': 'Group A', 'description': 'Sunday 1st floor'})
    .select().single();

await supabase.from('groups')
    .update({'name': 'Group A1'}).eq('id', group['id']).select();

// Membership
await supabase.from('group_members')
    .insert({'group_id': groupId, 'user_id': userId, 'role': 'member'}).select();

// Appoint a leader
await supabase.from('group_members')
    .update({'role': 'leader'})
    .eq('group_id', groupId).eq('user_id', userId).select();

// Move a user to another group: deactivate first, then insert.
// Inserting while the old membership is active violates the
// one-active-group-per-user index.
await supabase.from('group_members')
    .update({'is_active': false})
    .eq('group_id', oldGroupId).eq('user_id', userId).select();
await supabase.from('group_members')
    .insert({'group_id': newGroupId, 'user_id': userId}).select();
```

---

## 10. How denials look on the client

Three distinct shapes — the middle one is the easy mistake:

| Situation | What you get |
| --- | --- |
| No privilege on the table (e.g. any request while signed out) | `PostgrestException`, HTTP 401/403 |
| `INSERT` blocked by an RLS `WITH CHECK` | `PostgrestException`, code `42501`, "new row violates row-level security policy" |
| `UPDATE` / `DELETE` blocked by an RLS `USING` clause | **no error** — the rows are simply invisible, so 0 rows are affected |

Because of the third case, always chain `.select()` onto an update or delete and
check that you got a row back. Silently affecting zero rows is what a rejected
privilege escalation looks like.

Constraint violations worth handling explicitly:

| Code | Constraint | Meaning |
| --- | --- | --- |
| `23505` | `group_members_group_id_user_id_key` | user is already in that group |
| `23505` | `group_members_one_active_group_per_user_idx` | user already has an active group |
| `23505` | `groups_name_unique_idx` | a group with that name exists (case-insensitive) |
| `23514` | `profiles_display_name_length` | `display_name` empty or over 60 chars |
