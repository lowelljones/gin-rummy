-- Solo test: second seat is a server-driven dumb bot
alter table public.games
  add column if not exists is_bot_game boolean not null default false;

comment on column public.games.is_bot_game is 'If true, seat 1 is a server bot (GINRUMMY_BOT_USER_ID); no second human in lobby.';
