CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Allow the configured application role used by postgres-exporter to read stats
DO
$$
BEGIN
    EXECUTE format('GRANT pg_read_all_stats TO %I', current_user);
END;
$$;
