-- Allow a player to leave/forfeit an active game before it concludes.
-- The API marks the game "abandoned" and records who left so the other
-- player's state poll can show an "opponent left" screen.

alter table public.games drop constraint if exists games_status_check;
alter table public.games
  add constraint games_status_check check (status in ('active', 'completed', 'abandoned'));

alter table public.games
  add column if not exists abandoned_by uuid references auth.users (id) on delete set null;
alter table public.games
  add column if not exists abandoned_at timestamptz;
