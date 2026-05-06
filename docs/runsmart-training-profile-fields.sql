alter table public.profiles
    add column if not exists average_weekly_distance_km double precision,
    add column if not exists training_data_source text,
    add column if not exists training_data_updated_at timestamptz;

do $$
begin
    if not exists (
        select 1
        from pg_constraint
        where conname = 'profiles_training_data_source_check'
    ) then
        alter table public.profiles
            add constraint profiles_training_data_source_check
            check (
                training_data_source is null
                or training_data_source in ('manual', 'garmin', 'runSmart')
            )
            not valid;
    end if;
end $$;
