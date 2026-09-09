-- ============================================================================
-- Camplink — пример справочных/стартовых данных (опционально, п.8)
-- ВАЖНО: это иллюстративный seed. В реале наполняется данными владельца/бизнеса.
-- Применять строго ПОСЛЕ schema.sql.
-- ============================================================================

-- Ресурсы
INSERT INTO resource (name, description, item_type, unit_type, price, multiplicity, photo_url) VALUES
    ('Беседка «Сосна»',    'Беседка на 12 человек', 'rent',  'hour',  500.00,   1,   NULL),
    ('Палатка 2-местная',  'Туристическая палатка', 'rent',  'piece', 300.00,   1,   NULL),
    ('Дрова (мешок)',      'Сухие дрова',           'piece', 'kg',     50.00,   10,  NULL);

-- Клиент (пример)
INSERT INTO client (name, description, contacts) VALUES
    ('Иванов Иван Иванович', NULL, '+7 900 000-00-00, email@example.com');

-- Календарь (пример на неделю; NULL-calendar_id подставляется IDENTITY
-- INSERT ... один столбец на дату)
INSERT INTO calendar (date, day_type) VALUES
    ('2026-09-09'::date, 'working'),
    ('2026-09-10'::date, 'working'),
    ('2026-09-11'::date, 'working'),
    ('2026-09-12'::date, 'weekend'),
    ('2026-09-13'::date, 'weekend');

-- Ввод остатков (пример): беседка, 2026-09-09, слот 10:00 на 1 час — 2 шт. доступно
INSERT INTO inventory (resource_id, booking_id, movement_type, operation_type, calendar_id, reserved_time, event_time, quantity, price)
VALUES (
    (SELECT resource_id FROM resource WHERE name = 'Беседка «Сосна»'),
    NULL,
    'opening_balance',
    'reserved',
    (SELECT calendar_id FROM calendar WHERE date = '2026-09-09'::date),
    '2026-09-09 10:00'::timestamp,
    '2026-09-09 10:00'::timestamp,
    2,
    500.00
);
