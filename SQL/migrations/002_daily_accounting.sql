-- Применять при остановленном backend, от владельца таблиц.
-- psql -h localhost -U postgres -d camplink -v ON_ERROR_STOP=1 -f SQL/migrations/002_daily_accounting.sql
-- Неоднозначная история останавливает ВСЮ миграцию, без частичных изменений.
BEGIN;
LOCK TABLE public.resource, public.booking_line, public.inventory IN ACCESS EXCLUSIVE MODE;

ALTER TABLE public.inventory ADD COLUMN IF NOT EXISTS booking_line_id bigint;
ALTER TABLE public.booking_line ALTER COLUMN start_time DROP NOT NULL;
ALTER TABLE public.booking_line ALTER COLUMN end_time DROP NOT NULL;

-- Старые timestamp без зоны интерпретируются как UTC, повторный запуск безопасен.
DO $$
DECLARE col record;
BEGIN
    FOR col IN
        SELECT table_name, column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND data_type = 'timestamp without time zone'
          AND ((table_name = 'booking_line' AND column_name IN ('start_time', 'end_time'))
            OR (table_name = 'inventory' AND column_name IN ('reserved_time', 'event_time')))
    LOOP
        EXECUTE format('ALTER TABLE public.%I ALTER COLUMN %I TYPE timestamptz USING %I AT TIME ZONE ''UTC''',
            col.table_name, col.column_name, col.column_name);
    END LOOP;
END $$;

CREATE TEMP TABLE daily_migration_groups ON COMMIT DROP AS
SELECT i.resource_id, i.calendar_id, i.booking_id, i.booking_line_id, i.movement_type,
       min(i.inventory_id) AS keep_id, count(*) AS row_count,
       count(i.reserved_time) AS hour_count,
       count(DISTINCT i.reserved_time) AS distinct_hours,
       min(i.reserved_time) AS first_hour, max(i.reserved_time) AS last_hour,
       count(DISTINCT i.quantity) AS quantities,
       count(DISTINCT i.price) AS prices,
       count(DISTINCT i.operation_type) AS operations,
       count(DISTINCT coalesce(i.payment_type::text, '')) AS payments,
       min(i.quantity) AS quantity, min(i.price) AS price,
       max(i.event_time) AS event_time
FROM public.inventory i JOIN public.resource r USING (resource_id)
WHERE r.unit_type = 'day'
GROUP BY i.resource_id, i.calendar_id, i.booking_id, i.booking_line_id, i.movement_type;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM daily_migration_groups g JOIN public.calendar c USING (calendar_id)
        WHERE g.quantities <> 1 OR g.prices <> 1 OR g.operations <> 1 OR g.payments <> 1
           OR NOT (
               (g.row_count = 1 AND g.hour_count = 0)
               OR (g.row_count = 24 AND g.hour_count = 24 AND g.distinct_hours = 24
                   AND g.first_hour = c.date::timestamp AT TIME ZONE 'UTC'
                   AND g.last_hour = (c.date::timestamp + interval '23 hours') AT TIME ZONE 'UTC'
                   AND NOT EXISTS (
                       SELECT 1 FROM public.inventory i
                       WHERE i.resource_id = g.resource_id AND i.calendar_id = g.calendar_id
                         AND i.booking_id IS NOT DISTINCT FROM g.booking_id
                         AND i.booking_line_id IS NOT DISTINCT FROM g.booking_line_id
                         AND i.movement_type = g.movement_type
                         AND date_trunc('hour', i.reserved_time) <> i.reserved_time)))
           OR (g.movement_type = 'opening_balance' AND g.booking_id IS NOT NULL)
           OR g.movement_type = 'incoming'
    ) THEN
        RAISE EXCEPTION 'Неоднозначная суточная история: неполные/повторные часы, разные количество, цена, оплата или статус. Нужна ручная сверка; миграция отменена.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.booking_line l JOIN public.resource r USING (resource_id)
        JOIN public.calendar c USING (calendar_id)
        WHERE r.unit_type = 'day' AND (
            (l.start_time IS NULL AND l.end_time IS NULL)
            OR (l.start_time = c.date::timestamp AT TIME ZONE 'UTC'
                AND l.end_time = (c.date::timestamp + interval '1 day') AT TIME ZONE 'UTC')) IS NOT TRUE
    ) THEN
        RAISE EXCEPTION 'Найдены суточные позиции с неполным или многодневным интервалом. Нужна ручная сверка; миграция отменена.';
    END IF;
END $$;

CREATE TEMP TABLE daily_migration_lines ON COMMIT DROP AS
SELECT g.keep_id, min(l.booking_line_id) AS booking_line_id, count(l.booking_line_id) AS matches
FROM daily_migration_groups g
LEFT JOIN public.booking_line l ON l.booking_id = g.booking_id
    AND l.resource_id = g.resource_id AND l.calendar_id = g.calendar_id
    AND l.quantity = g.quantity AND l.price = g.price
    AND (g.booking_line_id IS NULL OR l.booking_line_id = g.booking_line_id)
WHERE g.movement_type = 'outgoing'
GROUP BY g.keep_id;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM daily_migration_lines WHERE matches <> 1) THEN
        RAISE EXCEPTION 'Невозможно однозначно связать суточный расход с позицией бронирования; миграция отменена.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.booking_line l JOIN public.resource r USING (resource_id)
        WHERE r.unit_type = 'day' AND NOT EXISTS (
            SELECT 1 FROM daily_migration_lines m WHERE m.booking_line_id = l.booking_line_id)
    ) THEN
        RAISE EXCEPTION 'У суточной позиции отсутствует однозначный расход в журнале; миграция отменена.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.inventory
        WHERE movement_type = 'opening_balance' AND reserved_time IS NULL
        GROUP BY resource_id, calendar_id HAVING count(*) > 1
    ) THEN
        RAISE EXCEPTION 'Обнаружены повторные дневные остатки; миграция отменена.';
    END IF;
END $$;

-- Архив исходных данных остаётся после успешной миграции (для сверки сумм и аудита).
CREATE TABLE IF NOT EXISTS public.inventory_before_daily_accounting AS
    SELECT * FROM public.inventory WITH NO DATA;
INSERT INTO public.inventory_before_daily_accounting
SELECT i.* FROM public.inventory i JOIN public.resource r USING (resource_id)
WHERE r.unit_type = 'day' AND NOT EXISTS (
    SELECT 1 FROM public.inventory_before_daily_accounting b WHERE b.inventory_id = i.inventory_id);
CREATE TABLE IF NOT EXISTS public.booking_line_before_daily_accounting AS
    SELECT l.* FROM public.booking_line l WITH NO DATA;
INSERT INTO public.booking_line_before_daily_accounting
SELECT l.* FROM public.booking_line l JOIN public.resource r USING (resource_id)
WHERE r.unit_type = 'day' AND NOT EXISTS (
    SELECT 1 FROM public.booking_line_before_daily_accounting b WHERE b.booking_line_id = l.booking_line_id);
CREATE TABLE IF NOT EXISTS public.resource_before_daily_accounting AS
    SELECT * FROM public.resource WITH NO DATA;
INSERT INTO public.resource_before_daily_accounting
SELECT r.* FROM public.resource r WHERE r.unit_type = 'day' AND NOT EXISTS (
    SELECT 1 FROM public.resource_before_daily_accounting b WHERE b.resource_id = r.resource_id);

DELETE FROM public.inventory i USING daily_migration_groups g
WHERE i.resource_id = g.resource_id AND i.calendar_id = g.calendar_id
    AND i.booking_id IS NOT DISTINCT FROM g.booking_id
    AND i.booking_line_id IS NOT DISTINCT FROM g.booking_line_id AND i.movement_type = g.movement_type
    AND i.inventory_id <> g.keep_id;
UPDATE public.inventory i SET reserved_time = NULL, event_time = g.event_time,
    operation_type = CASE WHEN i.movement_type = 'opening_balance'
                         THEN 'confirmed'::public.operation_type ELSE i.operation_type END
FROM daily_migration_groups g WHERE i.inventory_id = g.keep_id;
UPDATE public.inventory i SET booking_line_id = l.booking_line_id
FROM daily_migration_lines l WHERE i.inventory_id = l.keep_id;
UPDATE public.booking_line l SET start_time = NULL, end_time = NULL
FROM public.resource r WHERE l.resource_id = r.resource_id AND r.unit_type = 'day';

-- Одна выбранная дата = одни сутки. Прежнее значение 24 означало часы.
UPDATE public.resource SET multiplicity = 1 WHERE unit_type = 'day';

CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_daily_opening
    ON public.inventory (resource_id, calendar_id)
    WHERE movement_type = 'opening_balance' AND reserved_time IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_daily_booking_line
    ON public.inventory (booking_line_id, calendar_id)
    WHERE movement_type = 'outgoing' AND reserved_time IS NULL AND booking_line_id IS NOT NULL;
COMMIT;
