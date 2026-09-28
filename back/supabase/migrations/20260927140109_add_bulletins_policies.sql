-- =========================================================
-- bulletins RLS policies
-- =========================================================

alter table public.bulletins enable row level security;


-- ---------------------------------------------------------
-- SELECT
-- 승인된 사용자는 게시된 주보만 조회 가능
-- 관리자는 게시 여부와 관계없이 전체 조회 가능
-- ---------------------------------------------------------
drop policy if exists "bulletins_select" on public.bulletins;
create policy "bulletins_select"
on public.bulletins
for select
to authenticated
using (
  public.is_admin()
  or (
    public.is_approved()
    and is_published = true
  )
);


-- ---------------------------------------------------------
-- INSERT
-- 관리자만 생성 가능
-- ---------------------------------------------------------
drop policy if exists "bulletins_insert_admin" on public.bulletins;
create policy "bulletins_insert_admin"
on public.bulletins
for insert
to authenticated
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- UPDATE
-- 관리자만 수정 가능
-- ---------------------------------------------------------
drop policy if exists "bulletins_update_admin" on public.bulletins;
create policy "bulletins_update_admin"
on public.bulletins
for update
to authenticated
using (
  public.is_admin()
)
with check (
  public.is_admin()
);


-- ---------------------------------------------------------
-- DELETE
-- 관리자만 삭제 가능
-- ---------------------------------------------------------
drop policy if exists "bulletins_delete_admin" on public.bulletins;
create policy "bulletins_delete_admin"
on public.bulletins
for delete
to authenticated
using (
  public.is_admin()
);