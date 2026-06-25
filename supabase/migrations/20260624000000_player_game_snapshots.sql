-- Per-player, RLS-gated game snapshots for Supabase Realtime postgres_changes.
-- Each row holds the filtered perspective one seat is allowed to see (output of
-- buildPerspective on the API). Clients subscribe to their own row and render
-- directly — no pull from /games/:id/state on every opponent move.

create table if not exists public.player_game_snapshots (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  move_seq bigint not null default 0,
  perspective jsonb not null,
  status text not null,
  left_by_seat smallint check (left_by_seat is null or left_by_seat in (0, 1)),
  betting jsonb,
  opponent_display_name text not null default 'Opponent',
  rematch jsonb,
  lobby_invite_code text,
  updated_at timestamptz not null default now(),
  primary key (game_id, user_id)
);

create index if not exists player_game_snapshots_user_game_idx
  on public.player_game_snapshots (user_id, game_id);

alter table public.player_game_snapshots enable row level security;

-- Each player reads only their own snapshot row.
create policy player_game_snapshots_select_own
  on public.player_game_snapshots
  for select
  using (user_id = auth.uid());

-- Writes are API-only (service role); no client insert/update policies.

alter publication supabase_realtime add table public.player_game_snapshots;
