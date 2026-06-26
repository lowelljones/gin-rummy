-- UGC moderation: user blocks and chat message reports (Apple Guideline 1.2)

create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  check (blocker_id <> blocked_user_id)
);

create index if not exists user_blocks_blocker_idx on public.user_blocks (blocker_id);

create table if not exists public.chat_reports (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  message_id uuid not null references public.game_chat_messages (id) on delete cascade,
  reporter_id uuid not null references auth.users (id) on delete cascade,
  reported_user_id uuid not null references auth.users (id) on delete cascade,
  reason text,
  status text not null default 'pending' check (status in ('pending', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);

create index if not exists chat_reports_status_created_idx
  on public.chat_reports (status, created_at desc);

alter table public.user_blocks enable row level security;
alter table public.chat_reports enable row level security;
