ㅎㅇ

## Backend 1 — auth foundation

Identity, organization, and authorization live in `back/supabase/`. Start here:

- [`back/docs/TEAM_WALKTHROUGH.md`](back/docs/TEAM_WALKTHROUGH.md) — **read this first.** 15-minute plain-language tour of what exists, what each teammate has to do, and what we still need to decide ([한국어](back/docs/TEAM_WALKTHROUGH.ko.md))
- [`back/docs/BACKEND1_HANDOFF.md`](back/docs/BACKEND1_HANDOFF.md) — schema, roles, approval rules, admin bootstrap, setup steps, test checklist
- [`back/docs/FLUTTER_AUTH_INTEGRATION.md`](back/docs/FLUTTER_AUTH_INTEGRATION.md) — exact client calls for signup, signin, auto-login, approval gating
- [`back/docs/BACKEND2_RLS_CONTRACT.md`](back/docs/BACKEND2_RLS_CONTRACT.md) — how feature tables must use the authorization helpers

앱 전체 설계 (from the `260922` 안건):

- [`back/docs/SCREENS.md`](back/docs/SCREENS.md) — 화면 흐름도 27개 화면, 권한 게이트, 단계별 구분
- [`back/docs/ARCHITECTURE.md`](back/docs/ARCHITECTURE.md) — 백엔드 아키텍처, 3층 역할 모델, 테이블 18개, 헬퍼 함수 설계

Verify the migrations locally (needs only a running PostgreSQL, no Docker):

```bash
back/scripts/verify-local.sh
```
