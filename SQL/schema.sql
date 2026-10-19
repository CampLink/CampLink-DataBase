-- ============================================================================
-- Camplink — схема базы данных PostgreSQL
-- Источник истины: Scheme/DatabaseScheme.erd.json + Scheme/camplink.drawio
-- Генерация: вручную по ER-диаграмме
-- Общие решения:
--   * PK: BIGINT GENERATED ALWAYS AS IDENTITY (п.2)
--   * Enum-поля: нативные типы PostgreSQL ENUM (п.3)
--   * Схема: public (п.6)
--   * Имена таблиц/колонок на английском, комментарии — на русском
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3. Enum-типы
-- Соответствуют INT-полям ERD, закодированным enum'ом (значения см. в комментариях).
-- ----------------------------------------------------------------------------
CREATE TYPE resource_item_type AS ENUM ('piece', 'rent');        -- поштучный / прокатный
CREATE TYPE unit_type          AS ENUM ('piece', 'kg', 'liter', 'hour', 'day'); -- штука / кг / литр / час / сутки
CREATE TYPE movement_type      AS ENUM ('opening_balance', 'incoming', 'outgoing'); -- ввод остатков / приход / расход
CREATE TYPE operation_type     AS ENUM ('reserved', 'confirmed', 'purchased', 'canceled'); -- резерв / подтверждено / куплено / отменено
CREATE TYPE payment_type       AS ENUM ('cash', 'cashless');     -- нал / безнал
CREATE TYPE day_type           AS ENUM ('working', 'weekend', 'holiday'); -- рабочий / выходной / нерабочий

-- ----------------------------------------------------------------------------
-- Client (Клиенты)
-- ----------------------------------------------------------------------------
CREATE TABLE client (
    client_id   BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name        VARCHAR(200)  NOT NULL,                -- название
    description VARCHAR(1000),                          -- описание
    contacts    VARCHAR(200)                            -- контакты
);
COMMENT ON TABLE  client                IS 'Клиенты';
COMMENT ON COLUMN client.name           IS 'Название';
COMMENT ON COLUMN client.description    IS 'Описание';
COMMENT ON COLUMN client.contacts       IS 'Контакты';

-- ----------------------------------------------------------------------------
-- Resource (Ресурсы)
-- ----------------------------------------------------------------------------
CREATE TABLE resource (
    resource_id  BIGINT             GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         VARCHAR(200)       NOT NULL,                         -- название
    description  VARCHAR(1000),                                       -- описание
    item_type    resource_item_type NOT NULL,                         -- тип товара
    unit_type    unit_type          NOT NULL,                         -- ед. изм.
    price        NUMERIC(10,2)      NOT NULL CHECK (price >= 0),      -- цена за 1 ед. изм.
    multiplicity INTEGER,                                             -- кратность
    photo_url    VARCHAR(500)                                         -- ссылка на фото
);
COMMENT ON TABLE  resource               IS 'Ресурсы';
COMMENT ON COLUMN resource.name          IS 'Название';
COMMENT ON COLUMN resource.description   IS 'Описание';
COMMENT ON COLUMN resource.item_type     IS 'Тип товара: piece - поштучный, rent - прокатный';
COMMENT ON COLUMN resource.unit_type     IS 'Ед. изм.: piece - штука, kg - кг, liter - литр, hour - час, day - сутки';
COMMENT ON COLUMN resource.price         IS 'Цена за 1 ед. изм.';
COMMENT ON COLUMN resource.multiplicity  IS 'Кратность';
COMMENT ON COLUMN resource.photo_url     IS 'Ссылка на фото';

-- ----------------------------------------------------------------------------
-- Booking (Бронирования)
-- ----------------------------------------------------------------------------
CREATE TABLE booking (
    booking_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_id  BIGINT NOT NULL,
    CONSTRAINT fk_booking_client FOREIGN KEY (client_id)
        REFERENCES client (client_id) ON DELETE RESTRICT
);
COMMENT ON TABLE booking IS 'Бронирования';

-- ----------------------------------------------------------------------------
-- Calendar (Календарь)
-- Создаётся до BookingLine: booking_line ссылается на calendar (calendar_id).
-- ----------------------------------------------------------------------------
CREATE TABLE calendar (
    calendar_id BIGINT   GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date        DATE     NOT NULL UNIQUE,        -- дата (одна запись на дату)
    day_type    day_type NOT NULL                -- тип дня
);
COMMENT ON TABLE  calendar             IS 'Календарь';
COMMENT ON COLUMN calendar.date        IS 'Дата';
COMMENT ON COLUMN calendar.day_type    IS 'Тип дня: working - рабочий, weekend - выходной, holiday - нерабочий';

-- ----------------------------------------------------------------------------
-- BookingLine (Строки бронирования)
-- ----------------------------------------------------------------------------
CREATE TABLE booking_line (
    booking_line_id BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id      BIGINT        NOT NULL,
    resource_id     BIGINT        NOT NULL,
    client_id       BIGINT        NOT NULL,
    quantity        INTEGER       NOT NULL CHECK (quantity > 0),      -- количество
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),        -- цена за 1 кол-во
    calendar_id     BIGINT        NOT NULL,                             -- ссылка на справочник календарь
    start_time      TIMESTAMPTZ,                                          -- время начала
    end_time        TIMESTAMPTZ,                                          -- время окончания
    CONSTRAINT fk_booking_line_booking  FOREIGN KEY (booking_id)  REFERENCES booking  (booking_id)  ON DELETE CASCADE,
    CONSTRAINT fk_booking_line_calendar FOREIGN KEY (calendar_id) REFERENCES calendar (calendar_id) ON DELETE RESTRICT,
    CONSTRAINT fk_booking_line_resource FOREIGN KEY (resource_id) REFERENCES resource (resource_id) ON DELETE RESTRICT,
    CONSTRAINT fk_booking_line_client   FOREIGN KEY (client_id)   REFERENCES client   (client_id)   ON DELETE RESTRICT
);
COMMENT ON TABLE  booking_line               IS 'Строки бронирования';
COMMENT ON COLUMN booking_line.quantity      IS 'Количество';
COMMENT ON COLUMN booking_line.price         IS 'Цена за 1 кол-во';
COMMENT ON COLUMN booking_line.calendar_id   IS 'Ссылка на справочник календарь (дата строки бронирования)';
COMMENT ON COLUMN booking_line.start_time    IS 'Время начала';
COMMENT ON COLUMN booking_line.end_time      IS 'Время окончания';

-- ----------------------------------------------------------------------------
-- Inventory (Запасы, журнал движения)
-- ----------------------------------------------------------------------------
CREATE TABLE inventory (
    inventory_id    BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id     BIGINT        NOT NULL,
    booking_line_id BIGINT,                                             -- позиция бронирования, без FK
    booking_id      BIGINT,                                             -- NULL при "вводе остатков"
    movement_type   movement_type NOT NULL,                             -- тип движения
    operation_type  operation_type NOT NULL,                            -- тип операции
    payment_type    payment_type,                                       -- тип оплаты
    calendar_id     BIGINT        NOT NULL,                             -- ссылка на справочник календарь (зарезервированная дата)
    reserved_time   TIMESTAMPTZ,                                          -- зарезервированное время
    event_time      TIMESTAMPTZ,                                          -- время события
    quantity        INTEGER       NOT NULL CHECK (quantity >= 0),       -- количество
    price           NUMERIC(10,2) NOT NULL CHECK (price >= 0),          -- цена за 1 ед. изм.
    CONSTRAINT fk_inventory_resource FOREIGN KEY (resource_id) REFERENCES resource (resource_id) ON DELETE RESTRICT,
    CONSTRAINT fk_inventory_booking  FOREIGN KEY (booking_id)  REFERENCES booking  (booking_id)  ON DELETE SET NULL,
    CONSTRAINT fk_inventory_calendar FOREIGN KEY (calendar_id) REFERENCES calendar (calendar_id) ON DELETE RESTRICT
);
COMMENT ON TABLE  inventory                IS 'Запасы (журнал движения)';
COMMENT ON COLUMN inventory.resource_id    IS 'Ссылка на ресурс';
COMMENT ON COLUMN inventory.booking_id     IS 'Ссылка на бронирование (NULL при вводе остатков)';
COMMENT ON COLUMN inventory.movement_type  IS 'Тип движения: opening_balance - ввод остатков, incoming - приход, outgoing - расход';
COMMENT ON COLUMN inventory.operation_type IS 'Тип операции: reserved - резерв, confirmed - подтверждено, purchased - куплено, canceled - отменено';
COMMENT ON COLUMN inventory.payment_type   IS 'Тип оплаты: cash - нал, cashless - безнал';
COMMENT ON COLUMN inventory.calendar_id    IS 'Ссылка на справочник календарь (зарезервированная дата)';
COMMENT ON COLUMN inventory.reserved_time  IS 'Зарезервированное время';
COMMENT ON COLUMN inventory.event_time     IS 'Время события';
COMMENT ON COLUMN inventory.quantity       IS 'Количество';
COMMENT ON COLUMN inventory.price          IS 'Цена за 1 ед. изм.';

-- ----------------------------------------------------------------------------
-- 5. Индексы для FK-колонок (ускорение JOIN-ов)
-- ----------------------------------------------------------------------------
CREATE INDEX idx_booking_client        ON booking       (client_id);
CREATE INDEX idx_booking_line_booking  ON booking_line  (booking_id);
CREATE INDEX idx_booking_line_resource ON booking_line  (resource_id);
CREATE INDEX idx_booking_line_client   ON booking_line  (client_id);
CREATE INDEX idx_booking_line_calendar ON booking_line  (calendar_id);
CREATE INDEX idx_inventory_resource    ON inventory     (resource_id);
CREATE INDEX idx_inventory_booking     ON inventory     (booking_id);
CREATE INDEX idx_inventory_calendar    ON inventory     (calendar_id);

-- Уникальность слота «ввода остатков»: на дату (и час для прокатных) у ресурса —
-- одна строка ввода остатков.
CREATE UNIQUE INDEX uq_inventory_opening_balance
    ON inventory (resource_id, movement_type, calendar_id, reserved_time)
    WHERE movement_type = 'opening_balance';

-- Дневная запись не содержит reserved_time; NULL не защищён обычным UNIQUE.
CREATE UNIQUE INDEX uq_inventory_daily_opening
    ON inventory (resource_id, calendar_id)
    WHERE movement_type = 'opening_balance' AND reserved_time IS NULL;
CREATE UNIQUE INDEX uq_inventory_daily_booking_line
    ON inventory (booking_line_id, calendar_id)
    WHERE movement_type = 'outgoing' AND reserved_time IS NULL AND booking_line_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 6. (Опционально) роль приложения: права DML без DDL
-- ----------------------------------------------------------------------------
CREATE ROLE camplink_app LOGIN PASSWORD 'change_me';
 GRANT USAGE    ON SCHEMA public                    TO camplink_app;
 GRANT SELECT, INSERT, UPDATE, DELETE
       ON ALL TABLES IN SCHEMA public               TO camplink_app;
 GRANT USAGE, SELECT
       ON ALL SEQUENCES IN SCHEMA public            TO camplink_app;
 ALTER DEFAULT PRIVILEGES IN SCHEMA public
       GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO camplink_app;
 ALTER DEFAULT PRIVILEGES IN SCHEMA public
       GRANT USAGE, SELECT ON SEQUENCES             TO camplink_app;
