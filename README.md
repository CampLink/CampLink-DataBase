Camplink - сервис бронирования товаров и услуг на базе отдыха.

Проблема пользователя - заблоговременно спланировать свой отдых.
Проблема владельца - финансовый учёт, планирование и распределение ресурсов (товары, инвентарь, услуги).

Описание системы: 
Camplink должен предоставлять информацию о доступном количество ресурсов в разрезе даты для поштучных товаров, в разрезе дата-время для прокатных товаров. Для упращения работы с прокатом считаем, что весь прокатный инвентарь можно арендовать минимум на час, то есть минимальная единица учёта проката - час. Также для простоты учёта остатки товаров существуют только в рамках одной даты. Для некоторых прокатных товаров есть ограничение по минимальному времени бронирования, например беседку можно забронировать минимум на сутки.
Camplink должен учитывать ввод остатков и бронирования при расчёте доступного кол-ва.
Camplink должен владеть информацией о клиентах и их бронированиях.
Camplink должен предоставлять финансовую информацию владельцам.

ИНВЕНТАРИЗАЦИЯ - ВВОД ОСТАТКОВ

По каждому ресурсу создаётся журнал запасов с типом движения "ввод остатков" на конкретную дату. Если товар поштучный, то на конкретную дату создаётся одна строка с доступным количеством и ценой товара на этот день. Если товар прокатный, то создаётся не больше 24-х строк на каждый час в сутках.


ФИН. ОТЧЁТ

За указанный период формируется информация о запасах в статусе расход + куплено.


БРОНИРОВАНИЕ

Сервис должен уметь формировать список доступных русурсов на конкретную дату, уметь выполнять резерв ресурсов под конкретного клиента, знать информацию о всех бронированиях, учитывать статус оплат и бронирования.

Get:
формируется список доступных русурсов на конкретную дату.

Get: Клиент ID
формируется информация о бронированиях клиента

Get: Бронирование ID
формируется информация о бронированиях клиента

Post:
Добавляется запись в справочник клиентов, создаются записи в журналах бронирование и журналах запасов.
In:
Клиент
- название
- описание
- контакты
Ресурс
- Ресурс ID
- Количество
- Дата
- Время начала
- Время окончания
Out:
- Бронирование ID


УПРАВЛЕНИЕ ОПЛАТОЙ И БРОНИРОВАНИЕМ 

Записи запасов переходят в требуемый статус
In:
- Бронирование ID
- тип оплаты: нал, безнал
- статус оплаты: не оплачено, оплачено
- статус бронирования: подтверждено, отменено
Out:
сообщение об успешной оплате по бронированию или об успешном бронировании

_________________________________


Для работы необходимо учитывать сущности: ресурс, бронирование, клиент, запасы, календарь

Атрибуты сущности ресурсы:

- идентификатор (Ресурс ID)
- название
- описание
- тип товара: поштучный, прокатный
- ед. изм.: штука, кг, литр, час
- Цена за 1 ед. изм.
- Кратность
- ссылка на фото

Атрибуты сущности клиент:

- идентификатор (Клиент ID)
- название
- описание
- контакты

Атрибуты сущности бронирование:

- идентификатор (Бронирование ID)
- Ссылка Клиент ID

Строки бронирования:

- идентификатор (Строка бронирования ID)
- Ссылка Бронирование ID
- Ссылка Ресурс ID
- Ссылка Клиент ID
- Количество
- Цена за 1 кол-во
- дата
- Время начала
- Время окончания

Атрибуты сущности запасы:

- Ссылка Ресурс ID
- Ссылка Бронирование ID
- тип движения: ввод остатков, приход, расход
- тип операции: резерв, подтверждено, куплено, отменено
- тип оплаты: нал, безнал
- зарезервированная дата
- зарезервированное время
- время события
- количество
- Цена за 1 ед. изм.

Атрибуты сущности календарь:

- дата
- тип нерабочий/рабочий/выходной

_____

Почитать:
марк даун, переписать ридми
абсидеан

Задачи:
установить марк даун ридер
нарисовать bpmn 2.0