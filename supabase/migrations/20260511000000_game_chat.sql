-- Per-game chat messages (API writes via service role; RLS for optional direct client reads)

create table if not exists public.game_chat_messages (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists game_chat_messages_game_created_idx
  on public.game_chat_messages (game_id, created_at);

alter table public.game_chat_messages enable row level security;

create policy game_chat_messages_select_participants
  on public.game_chat_messages
  for select
  using (
    exists (
      select 1 from public.games g
      where g.id = game_chat_messages.game_id
        and auth.uid() = any (g.player_ids)
    )
  );
