ㅎㅇ

## Backend 1 — auth foundation

Identity, organization, and authorization live in `back/supabase/`. Start here:

- [`back/docs/TEAM_WALKTHROUGH.md`](back/docs/TEAM_WALKTHROUGH.md) — **read this first.** 15-minute plain-language tour of what exists, what each teammate has to do, and what we still need to decide
- [`back/docs/BACKEND1_HANDOFF.md`](back/docs/BACKEND1_HANDOFF.md) — schema, roles, approval rules, admin bootstrap, setup steps, test checklist
- [`back/docs/FLUTTER_AUTH_INTEGRATION.md`](back/docs/FLUTTER_AUTH_INTEGRATION.md) — exact client calls for signup, signin, auto-login, approval gating
- [`back/docs/BACKEND2_RLS_CONTRACT.md`](back/docs/BACKEND2_RLS_CONTRACT.md) — how feature tables must use the authorization helpers

Verify the migrations locally (needs only a running PostgreSQL, no Docker):

```bash
back/scripts/verify-local.sh
```
