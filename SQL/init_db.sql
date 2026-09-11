-- ============================================================================
-- Camplink — инициализация роли и базы данных (запускать ОДИН раз)
-- Создаёт:
--   * роль приложения camplink_app (логин)
--   * базу данных camplink (владелец postgres)
-- Идемпотентно: повторный запуск не ломает ничего.
-- Применение: psql -U postgres -h localhost -f SQL/init_db.sql
-- После этого: psql -U postgres -h localhost -d camplink -f SQL/schema.sql
-- ============================================================================

-- Роль приложения (если ещё не существует)
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'camplink_app') THEN
        CREATE ROLE camplink_app LOGIN PASSWORD '456963';
    END IF;
END
$$;

-- База данных (если ещё не существует).
-- CREATE DATABASE нельзя выполнить в блоке DO, поэтому генерируем через \gexec.
SELECT 'CREATE DATABASE camplink OWNER postgres'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'camplink')\gexec

-- Права для роли приложения выдаются схемой (блок роли в schema.sql, см. ниже).