-- Upgrade path if 20260611000000 was applied with hand_index + attempt (no deal_index).

alter table public.hand_episodes
  add column if not exists deal_index int,
  add column if not exists started_at_move_seq bigint;

-- Best-effort backfill: treat attempt as deal ordinal within game when deal_index is missing.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'hand_episodes' and column_name = 'attempt'
  ) then
    update public.hand_episodes e
    set deal_index = sub.rn - 1
    from (
      select id, row_number() over (partition by game_id order by hand_index, attempt, ended_at_move_seq) as rn
      from public.hand_episodes
      where deal_index is null
    ) sub
    where e.id = sub.id and e.deal_index is null;

    alter table public.hand_episodes drop constraint if exists hand_episodes_game_id_hand_index_attempt_key;
    alter table public.hand_episodes drop column if exists attempt;
  end if;
end $$;

alter table public.hand_episodes alter column deal_index set not null;

alter table public.hand_episodes drop constraint if exists hand_episodes_game_id_deal_index_key;
alter table public.hand_episodes add constraint hand_episodes_game_id_deal_index_key unique (game_id, deal_index);

create index if not exists hand_episodes_game_deal_idx on public.hand_episodes (game_id, deal_index);

alter table public.game_moves add column if not exists deal_index int;
alter table public.game_moves drop column if exists hand_attempt;

drop index if exists public.game_moves_game_hand_idx;
create index if not exists game_moves_game_deal_idx on public.game_moves (game_id, deal_index);
