-- Per-player ready flag for the human-vs-human lobby flow.
-- Both seats must flip ready=true before the server creates a game; this replaces
-- the old "host taps Start" path for human matches. Bot games (is_bot_game=true)
-- still use POST /lobbies/:code/start with bot=true and bypass this column.

alter table public.lobby_players
  add column if not exists ready boolean not null default false;

comment on column public.lobby_players.ready is
  'True once this seat has tapped Ready in the lobby waiting room. When both seats are ready the API auto-creates the game.';
