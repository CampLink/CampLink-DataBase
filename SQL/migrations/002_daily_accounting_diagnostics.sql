-- Только чтение. После неудачной миграции сначала отдельно выполните ROLLBACK.
-- Работает до добавления inventory.booking_line_id и после него.
-- Старые timestamp без зоны трактуются как UTC, аналогично миграции 002.
BEGIN READ ONLY;
SET LOCAL TIME ZONE 'UTC';

WITH entries AS (
    SELECT i.inventory_id, i.resource_id, r.name AS resource_name,
           i.calendar_id, c.date, i.booking_id,
           (to_jsonb(i)->>'booking_line_id')::bigint AS booking_line_id,
           i.movement_type, i.operation_type, i.payment_type, i.quantity, i.price,
           i.reserved_time::timestamptz AS reserved_time
    FROM public.inventory i
    JOIN public.resource r USING (resource_id)
    JOIN public.calendar c USING (calendar_id)
    WHERE r.unit_type = 'day'
), groups AS (
    SELECT resource_id, resource_name, calendar_id, date, booking_id, booking_line_id, movement_type,
           count(*) AS row_count, count(reserved_time) AS hour_count,
           count(DISTINCT reserved_time) AS distinct_hours,
           min(reserved_time) AS first_hour, max(reserved_time) AS last_hour,
           bool_and(reserved_time = date_trunc('hour', reserved_time)) AS aligned_hours,
           array_agg(DISTINCT quantity) AS quantities,
           array_agg(DISTINCT price) AS prices,
           array_agg(DISTINCT operation_type::text) AS operations,
           array_agg(DISTINCT coalesce(payment_type::text, 'NULL')) AS payments,
           array_agg(inventory_id ORDER BY inventory_id) AS inventory_ids
    FROM entries
    GROUP BY resource_id, resource_name, calendar_id, date, booking_id, booking_line_id, movement_type
), problems AS (
    SELECT *, array_remove(ARRAY[
        CASE WHEN cardinality(quantities) <> 1 THEN 'Разное количество' END,
        CASE WHEN cardinality(prices) <> 1 THEN 'Разная цена' END,
        CASE WHEN cardinality(operations) <> 1 THEN 'Разные статусы операции' END,
        CASE WHEN cardinality(payments) <> 1 THEN 'Разные способы оплаты' END,
        CASE WHEN NOT (
            (row_count = 1 AND hour_count = 0)
            OR (row_count = 24 AND hour_count = 24 AND distinct_hours = 24
                AND first_hour = date::timestamp AT TIME ZONE 'UTC'
                AND last_hour = (date::timestamp + interval '23 hours') AT TIME ZONE 'UTC'
                AND aligned_hours))
            THEN 'Набор не является одной дневной записью или полными 24 часами UTC' END,
        CASE WHEN movement_type = 'opening_balance' AND booking_id IS NOT NULL
            THEN 'Ввод остатков связан с бронированием' END,
        CASE WHEN movement_type = 'incoming' THEN 'Движение incoming требует отдельной сверки' END
    ], NULL) AS reasons
    FROM groups
)
SELECT resource_id, resource_name, date, calendar_id, booking_id, booking_line_id,
       movement_type, reasons, row_count, hour_count, distinct_hours,
       first_hour, last_hour, quantities, prices, operations, payments, inventory_ids
FROM problems
WHERE cardinality(reasons) > 0
ORDER BY date, resource_id, booking_id, movement_type;

-- Второй набор результатов: позиции бронирования с неподходящим интервалом.
-- Приведение к timestamptz при UTC-сессии повторяет трактовку времени в миграции.
SELECT l.booking_line_id, l.booking_id, l.resource_id, r.name AS resource_name,
       c.date AS booking_date, l.quantity, l.price,
       l.start_time, l.end_time,
       extract(epoch FROM (l.end_time::timestamptz - l.start_time::timestamptz)) / 3600 AS duration_hours,
       CASE
           WHEN l.start_time IS NULL OR l.end_time IS NULL THEN 'Заполнена только одна граница интервала'
           WHEN l.end_time::timestamptz <= l.start_time::timestamptz THEN 'Окончание не позже начала'
           WHEN l.end_time::timestamptz - l.start_time::timestamptz > interval '1 day' THEN 'Многодневный интервал'
           ELSE 'Интервал не совпадает с полными сутками даты бронирования UTC'
       END AS reason
FROM public.booking_line l
JOIN public.resource r USING (resource_id)
JOIN public.calendar c USING (calendar_id)
WHERE r.unit_type = 'day' AND (
    (l.start_time IS NULL AND l.end_time IS NULL)
    OR (l.start_time::timestamptz = c.date::timestamp AT TIME ZONE 'UTC'
        AND l.end_time::timestamptz = (c.date::timestamp + interval '1 day') AT TIME ZONE 'UTC')
) IS NOT TRUE
ORDER BY c.date, l.resource_id, l.booking_id, l.booking_line_id;

COMMIT;
