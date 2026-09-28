-- 기존 권한을 정리하고 필요한 작업만 허용
revoke all on table public.bulletins from anon, authenticated;

grant select, insert, delete
  on table public.bulletins
  to authenticated;

grant update (title, bulletin_date, notion_url, is_published)
  on table public.bulletins
  to authenticated;