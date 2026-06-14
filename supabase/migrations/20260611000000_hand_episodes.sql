-- Analytics: one row per deal (every shuffle) and lightweight move indexing.
--
-- hand_index  = scoreboard hand # (unchanged on void/re-deal until points are awarded)
-- deal_index    = monotonic deal counter per game (increments on every new deal)

create table if not exists public.hand_episodes (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  deal_index int not null,
  hand_index int not null,
  dealer_seat smallint not null check (dealer_seat in (0, 1)),
  non_dealer_seat smallint not null check (non_dealer_seat in (0, 1)),
  knock_check_card text,
  outcome text not null check (
    outcome in (
      'gin',
      'bigGin',
      'knock',
      'undercut',
      'playedThrough',
      'mutualRedeal'
    )
  ),
  winner_seat smallint check (winner_seat in (0, 1)),
  closer_seat smallint check (closer_seat in (0, 1)),
  points_awarded int not null default 0,
  scores_before int[2] not null,
  scores_after int[2] not null,
  opening_hands jsonb not null,
  result jsonb,
  started_at_move_seq bigint,
  ended_at_move_seq bigint not null,
  created_at timestamptz not null default now(),
  unique (game_id, deal_index)
);

create index if not exists hand_episodes_game_hand_idx on public.hand_episodes (game_id, hand_index);
create index if not exists hand_episodes_game_deal_idx on public.hand_episodes (game_id, deal_index);

alter table public.hand_episodes enable row level security;

create policy hand_episodes_select_participants on public.hand_episodes for select using (
  exists (
    select 1 from public.games g
    where g.id = hand_episodes.game_id
      and auth.uid() = any (g.player_ids)
  )
);

-- Pre-move context on each move; legal actions are derived offline from server_truth.
alter table public.game_moves
  add column if not exists actor_seat smallint check (actor_seat in (0, 1)),
  add column if not exists deal_index int,
  add column if not exists hand_index int,
  add column if not exists phase text,
  add column if not exists stock_count int;

create index if not exists game_moves_game_deal_idx on public.game_moves (game_id, deal_index);
