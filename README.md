## Схема БД (актуальное состояние)

Источник истины — `Scheme/DatabaseScheme.erd.json` (ERD Editor). Схема отражает
доменные таблицы DWH из `Scheme/camplink.drawio`. Таблицы и колонки — на
английском, enum-значения указаны в комментариях к колонкам (см. файл схемы).

### Client (Клиенты)
- `ClientId` BIGINT PK
- `Name` VARCHAR — название
- `Description` VARCHAR — описание
- `Contacts` VARCHAR — контакты

### Resource (Ресурсы)
- `ResourceId` BIGINT PK
- `Name` VARCHAR — название
- `Description` VARCHAR — описание
- `ItemType` INT — тип товара: поштучный / прокатный
- `UnitType` INT — ед. изм.: штука / кг / литр / час
- `Price` DECIMAL(10,2) — цена за 1 ед. изм.
- `Multiplicity` INT — кратность
- `PhotoUrl` VARCHAR — ссылка на фото

### Booking (Бронирования)
- `BookingId` BIGINT PK
- `ClientId` BIGINT FK → `Client.ClientId`

### BookingLine (Строки бронирования)
- `BookingLineId` BIGINT PK
- `BookingId` BIGINT FK → `Booking.BookingId`
- `ResourceId` BIGINT FK → `Resource.ResourceId`
- `ClientId` BIGINT FK → `Client.ClientId`
- `Quantity` INT — количество
- `Price` DECIMAL(10,2) — цена за 1 кол-во
- `CalendarId` BIGINT FK → `Calendar.CalendarId` — дата строки бронирования
- `StartTime` DATETIME — время начала
- `EndTime` DATETIME — время окончания

### Inventory (Запасы, журнал движения)
- `InventoryId` BIGINT PK
- `ResourceId` BIGINT FK → `Resource.ResourceId`
- `BookingId` BIGINT FK → `Booking.BookingId` (nullable — пусто при «вводе остатков»)
- `MovementType` INT — тип движения: ввод остатков / приход / расход
- `OperationType` INT — тип операции: резерв / подтверждено / куплено / отменено
- `PaymentType` INT — тип оплаты: нал / безнал
- `CalendarId` BIGINT FK → `Calendar.CalendarId` — зарезервированная дата
- `ReservedTime` DATETIME — зарезервированное время
- `EventTime` DATETIME — время события
- `Quantity` INT — количество
- `Price` DECIMAL(10,2) — цена за 1 ед. изм.

### Calendar (Календарь)
- `CalendarId` BIGINT PK
- `Date` DATE — дата
- `DayType` INT — тип дня: рабочий / выходной / нерабочий

### Связи (FK, 1:N)

FK-связи (рёбра ERD) отмечены колонками со ссылкой на PK родительской таблицы;
графически рёбра расставляются в ERD Editor. Все связи — **1:N (One-to-Many)**,
ненаследуемые (non-identifying), FK живут на стороне Many.

| № | From (Many, FK) | To (One, PK) | Связь |
|---|---|---|---|
| 1 | `Booking.ClientId` | `Client.ClientId` | Client 1—N Booking |
| 2 | `BookingLine.BookingId` | `Booking.BookingId` | Booking 1—N BookingLine |
| 3 | `BookingLine.ClientId` | `Client.ClientId` | Client 1—N BookingLine |
| 4 | `BookingLine.ResourceId` | `Resource.ResourceId` | Resource 1—N BookingLine |
| 5 | `Inventory.ResourceId` | `Resource.ResourceId` | Resource 1—N Inventory |
| 6 | `Inventory.BookingId` | `Booking.BookingId` | Booking 1—N Inventory |
| 7 | `BookingLine.CalendarId` | `Calendar.CalendarId` | Calendar 1—N BookingLine |
| 8 | `Inventory.CalendarId` | `Calendar.CalendarId` | Calendar 1—N Inventory |

Семантика: один клиент — много бронирований; бронирование — много строк
бронирования; ресурс встречается в строках бронирования и имеет журнал запасов;
бронирование порождает записи в журнале запасов; дата строки бронирования
задаётся ссылкой на справочник календарь.

### DDL для PostgreSQL

Исполняемая схема для PostgreSQL сгенерирована по ER-диаграмме. Порядок
применения: `SQL/init_db.sql` (роль + БД) → `SQL/schema.sql` (схема) →
`SQL/seed.sql` (пример данных). Решения при генерации:

- PK — `BIGINT GENERATED ALWAYS AS IDENTITY`;
- enum-поля (`ItemType`, `UnitType`, `MovementType`, `OperationType`,
  `PaymentType`, `DayType`) — нативные типы PostgreSQL `ENUM`;
- схема — `public`;
- FK-колонки покрыты индексами; `Calendar.date` — `UNIQUE`;
  слот «ввода остатков» — частичный уникальный индекс;
- поведение `ON DELETE`: CASCADE для строк бронирования, RESTRICT для ссылок
  на клиента/ресурс, SET NULL для `Inventory.booking_id`.
