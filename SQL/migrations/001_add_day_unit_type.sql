-- Добавляет единицу «сутки» в существующую базу без пересоздания таблиц.
-- Запускать от владельца типа в базе, к которой подключён backend:
-- psql -h localhost -U postgres -d camplink -v ON_ERROR_STOP=1 -f SQL/migrations/001_add_day_unit_type.sql
-- Применять отдельно от операций, использующих новое значение enum.
ALTER TYPE public.unit_type ADD VALUE IF NOT EXISTS 'day' AFTER 'hour';
