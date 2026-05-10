-- Gin Rummy skeleton schema
-- Apply in Supabase SQL editor or via supabase db push

create extension if not exists "pgcrypto";

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  created_at timestamptz not null default now()
);

create table if not exists public.lobbies (
  id uuid primary key default gen_random_uuid(),
  invite_code text not null unique,
  status text not null default 'open' check (status in ('open', 'in_game', 'closed')),
  created_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.lobby_players (
  lobby_id uuid not null references public.lobbies (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  seat smallint not null check (seat in (0, 1)),
  joined_at timestamptz not null default now(),
  primary key (lobby_id, user_id),
  unique (lobby_id, seat)
);

create table if not exists public.games (
  id uuid primary key default gen_random_uuid(),
  lobby_id uuid not null references public.lobbies (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'completed')),
  race_target int not null default 125,
  player_ids uuid[2] not null,
  seat_for_user jsonb not null default '{}'::jsonb,
  server_truth jsonb not null,
  move_seq bigint not null default 0,
  current_hand_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.hands (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  index int not null,
  dealer_seat smallint not null check (dealer_seat in (0, 1)),
  outcome text,
  points_awarded int,
  created_at timestamptz not null default now(),
  unique (game_id, index)
);

create table if not exists public.game_moves (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  hand_id uuid references public.hands (id) on delete set null,
  seq bigint not null,
  actor_user_id uuid references auth.users (id) on delete set null,
  intent_type text not null,
  intent_payload jsonb not null default '{}'::jsonb,
  server_truth jsonb not null,
  perspectives jsonb not null,
  created_at timestamptz not null default now(),
  unique (game_id, seq)
);

create index if not exists game_moves_game_id_seq_idx on public.game_moves (game_id, seq);

-- RLS
alter table public.profiles enable row level security;
alter table public.lobbies enable row level security;
alter table public.lobby_players enable row level security;
alter table public.games enable row level security;
alter table public.hands enable row level security;
alter table public.game_moves enable row level security;

-- Profiles: users manage own row
create policy profiles_select_self on public.profiles for select using (auth.uid() = id);
create policy profiles_insert_self on public.profiles for insert with check (auth.uid() = id);
create policy profiles_update_self on public.profiles for update using (auth.uid() = id);

-- Lobbies readable if member or creator
create policy lobbies_select on public.lobbies for select using (
  created_by = auth.uid()
  or exists (
    select 1 from public.lobby_players lp
    where lp.lobby_id = lobbies.id and lp.user_id = auth.uid()
  )
);

create policy lobbies_insert on public.lobbies for insert with check (created_by = auth.uid());

create policy lobbies_update_creator on public.lobbies for update using (created_by = auth.uid());

-- Lobby players
create policy lobby_players_select on public.lobby_players for select using (
  exists (
    select 1 from public.lobby_players lp2
    where lp2.lobby_id = lobby_players.lobby_id and lp2.user_id = auth.uid()
  )
);

create policy lobby_players_insert_self on public.lobby_players for insert with check (user_id = auth.uid());

-- Games: participants read
create policy games_select_participants on public.games for select using (
  auth.uid() = any (player_ids)
);

-- No direct client writes to games / hands / game_moves (API uses service role)

create policy hands_select_participants on public.hands for select using (
  exists (
    select 1 from public.games g
    where g.id = hands.game_id
      and auth.uid() = any (g.player_ids)
  )
);

create policy game_moves_select_participants on public.game_moves for select using (
  exists (
    select 1 from public.games g
    where g.id = game_moves.game_id
      and auth.uid() = any (g.player_ids)
  )
);
