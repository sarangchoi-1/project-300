create table public.bulletins 
(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  bulletin_date date not null unique,
  notion_url text not null,
  is_published boolean not null default false,
  created_at timestamptz not null default now(),

  constraint bulletins_title_not_empty
    check (length(trim(title)) > 0),

  constraint bulletins_url_https
    check (notion_url like 'https://%')
);

-- 주보 데이터 접근 보호
alter table public.bulletins enable row level security;

-- 회원·관리자 정책을 연결하기 전까지 앱의 접근 차단
revoke all on table public.bulletins from anon, authenticated;