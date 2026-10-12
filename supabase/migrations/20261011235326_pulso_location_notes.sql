-- Public navigation instructions only; owner policies already protect writes.
alter table public.shops add column location_notes text not null default '' check(char_length(location_notes)<=300);
comment on column public.shops.location_notes is 'Public entrance, floor and landmark instructions supplied by the shop owner.';
