# Bedolaga Auto-Installer

Автоматическая установка [Bedolaga](https://docs.bedolagam.ru) — Telegram-бота для продажи VPN-подписок на базе [Remnawave](https://docs.rw).

---

## Быстрый старт

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USER/bedolaga_installer/main/install_bedolaga.sh | bash
```

> Требует root и работающей Remnawave Panel.

---

## Что делает скрипт

| Шаг | Действие |
|-----|----------|
| 1 | Проверяет Docker, Git, Remnawave Panel |
| 2 | Задаёт параметры (токен бота, топики, название сервиса) |
| 3 | Генерирует пароли и секреты автоматически |
| 4 | Клонирует репозиторий бота |
| 5 | Создаёт `.env` с полной конфигурацией |
| 6 | Подключает бот к сети Remnawave |
| 7 | Собирает Docker-образ и запускает контейнеры |
| 8 | Прописывает вебхук в Remnawave `.env` |
| 9 | Устанавливает certbot hook для TLS-уведомлений |
| 10 | Проверяет состояние и выводит итог |

---

## Требования

- **ОС:** Ubuntu 22.04 / Debian 12 (и выше)
- **Remnawave Panel:** установлена в `/opt/remnawave`, контейнеры запущены
- **Docker:** версия ≥ 20.10 с плагином `compose` v2
- **Root:** обязательно

---

## Параметры установки

Скрипт спросит следующее:

### Обязательные

| Параметр | Описание | Пример |
|----------|----------|--------|
| `BOT_TOKEN` | Токен бота от @BotFather | `1234567890:ABCDEFGHIJKLMNOPQRSTUVWXYZabcde` |
| `ADMIN_IDS` | Telegram ID администраторов (через запятую) | `123456789` |
| `REMNAWAVE_API_KEY` | API-ключ из панели Remnawave → Настройки → API Keys | `rw_XXXXXXXX...` |
| `NOTIF_CHAT_ID` | ID группы для уведомлений (начинается с -100...) | `-1001234567890` |

### Топики (с дефолтами)

| Переменная | Куда идут уведомления | Дефолт |
|-----------|----------------------|--------|
| `TOPIC_GENERAL` | Покупки, продления, триалы, баланс, промо, партнёры | `2` |
| `TOPIC_NODE` | Ноды, CRM-биллинг, сервис, ошибки | `441` |
| `TOPIC_REPORTS` | Ежедневные/недельные отчёты о продажах | `6` |
| `TOPIC_TICKETS` | Тикеты поддержки | `11` |
| `TOPIC_BACKUP` | Бекапы, ротация логов, TLS-сертификаты | `13` |

> **Примечание:** Bedolaga не разделяет события ноды, CRM и сервис внутри одной категории.
> Все попадают в `TOPIC_NODE`. Разделение по разным топикам требует изменения кода бота.

### Название сервиса

| Параметр | Описание | Пример |
|----------|----------|--------|
| `MINIAPP_NAME_RU` | Название на русском (показывается пользователям) | `TorchVPN` |
| `MINIAPP_NAME_EN` | Название на английском | `TorchVPN` |

---

## Управление после установки

```bash
# Команда для управления (устанавливается в /usr/local/bin/bedolaga)
bedolaga            # повторная установка или обновление

# Логи бота
cd /opt/bedolaga && docker compose logs -f bot

# Перезапуск
cd /opt/bedolaga && docker compose restart bot

# Остановка
cd /opt/bedolaga && docker compose down

# Редактировать конфиг
nano /opt/bedolaga/.env
cd /opt/bedolaga && docker compose restart bot  # применить изменения
```

---

## Все уведомления — куда и о чём

### Топик NODE (дефолт: 441) — инфраструктура

| Событие | Описание |
|---------|----------|
| `node.connection_lost` | Потеряно соединение с нодой |
| `node.connection_restored` | Соединение восстановлено |
| `node.created` | Нода создана в панели |
| `node.modified` | Параметры ноды изменены |
| `node.disabled` | Нода отключена |
| `node.enabled` | Нода включена |
| `node.deleted` | Нода удалена |
| `service.panel_started` | Панель Remnawave запущена |
| `service.login_attempt_success` | Успешный вход в панель |
| `service.login_attempt_failed` | Неудачная попытка входа |
| `service.subpage_config_changed` | Изменён конфиг страницы подписки |
| `crm.infra_billing_node_payment_in_7_days` | Оплата ноды через 7 дней |
| `crm.infra_billing_node_payment_in_48hrs` | Оплата ноды через 48 часов |
| `crm.infra_billing_node_payment_in_24hrs` | Оплата ноды через 24 часа |
| `crm.infra_billing_node_payment_due_today` | Оплата ноды сегодня |
| `crm.infra_billing_node_payment_overdue_24hrs` | Просрочка 24 часа |
| `crm.infra_billing_node_payment_overdue_48hrs` | Просрочка 48 часов |
| `crm.infra_billing_node_payment_overdue_7_days` | Просрочка 7 дней |
| `errors.*` | Системные ошибки, лимиты уведомлений |
| Обновление бота | Доступна новая версия Bedolaga |
| Режим обслуживания | Автовключение при критических ошибках |

### Топик TRAFFIC (дефолт: 6) — трафик и отчёты

| Событие | Описание |
|---------|----------|
| `node.traffic_notify` | Превышен лимит трафика ноды |
| Ежедневный отчёт | Продажи/конверсии/пользователи за вчера (в 10:00) |
| Недельный отчёт | Итог недели (раз в неделю) |

### Топик GENERAL (дефолт: 2) — продажи и клиенты

| Событие | Описание |
|---------|----------|
| Покупка подписки | Оплата прошла, подписка создана |
| Покупка с лендинга | Оплата через веб-страницу |
| Продление подписки | Ручное продление |
| Автопродление | Списание с баланса |
| Активация триала | Новый пробный период |
| Пополнение баланса | Пополнение внутреннего счёта |
| Докупка трафика | Дополнительный трафик куплен |
| Промокод применён | Скидка по коду |
| Переход по кампании | Клик по UTM-ссылке |
| Регистрация по кампании | Новый пользователь пришёл по UTM |
| Партнёрская заявка | Запрос на партнёрство |
| Запрос на вывод | Партнёр запросил выплату |

### Топик TICKETS (дефолт: 11) — поддержка

| Событие | Описание |
|---------|----------|
| Новый тикет | Пользователь открыл обращение |
| Ответ пользователя | Ответ пришёл в открытый тикет |
| SLA нарушен | Тикет без ответа более N минут |

### Топик BACKUP (дефолт: 13) — бекапы, логи, TLS

| Событие | Описание |
|---------|----------|
| Бекап создан | Ежедневный бекап БД (в 01:00) |
| Ошибка бекапа | Не удалось создать бекап (дублируется в топик NODE) |
| Ротация логов | Архивирование логов (в 00:00) |
| TLS-сертификат обновлён | Certbot hook при автообновлении |

### В личку пользователю (webhook → его DM)

| Событие | Описание |
|---------|----------|
| `user.expired` | Подписка истекла |
| `user.disabled` | Подписка отключена |
| `user.enabled` | Подписка активирована |
| `user.limited` | Трафик исчерпан |
| `user.revoked` | Подписка отозвана |
| `user.deleted` | Аккаунт удалён |
| `user.modified` | Параметры подписки изменены |
| `user.created` | Подписка создана |
| `user.expires_in_72_hours` | До истечения 72 часа |
| `user.expires_in_48_hours` | До истечения 48 часов |
| `user.expires_in_24_hours` | До истечения 24 часа |
| `user.expired_24_hours_ago` | Подписка истекла 24 ч назад ⚠️ нельзя отключить только для триала |
| `user.traffic_reset` | Трафик сброшен |
| `user.bandwidth_usage_threshold_reached` | Использовано 90% трафика |
| `user.first_connected` | Первое подключение к VPN |
| `user.not_connected` | Не подключился за N дней |
| `user_hwid_devices.added` | Добавлено новое устройство |
| `user_hwid_devices.deleted` | Устройство удалено |
| `torrent_blocker.report` | Обнаружен торрент-трафик |

> ⚠️ Событие `user.expired_24_hours_ago` нельзя отключить только для триалов.
> `WEBHOOK_NOTIFY_SUB_EXPIRED=false` отключает его для **всех** подписок.

---

## Симуляция уведомлений

```bash
# Запустить полную симуляцию всех уведомлений
bash /opt/bedolaga/test_notifications.sh --all

# Только внутренние события бота (покупки, тикеты, бекапы)
bash /opt/bedolaga/test_notifications.sh --internal

# Только сервис/CRM через webhook
bash /opt/bedolaga/test_notifications.sh --admin

# Только пользовательские события (нужен /start в боте)
bash /opt/bedolaga/test_notifications.sh --user

# Одиночное событие
bash /opt/bedolaga/test_notifications.sh --event user.expired

# Тест TLS-хука
bash /opt/bedolaga/test_notifications.sh --tls-test
```

---

## TLS-уведомления (certbot)

После установки скрипт автоматически создаёт certbot deploy hook:

```
/etc/letsencrypt/renewal-hooks/deploy/bedolaga-tls-notify.sh
```

Certbot вызывает его после каждого успешного обновления сертификата.
В Telegram топик 13 придёт сообщение с доменами и новой датой истечения.

**Проверить хук вручную:**
```bash
RENEWED_LINEAGE=/etc/letsencrypt/live/ВАШ_ДОМЕН \
RENEWED_DOMAINS="ВАШ_ДОМЕН" \
bash /etc/letsencrypt/renewal-hooks/deploy/bedolaga-tls-notify.sh
```

---

## Платёжные системы

По умолчанию все системы выключены. Включить в `/opt/bedolaga/.env`:

```env
# YooKassa
YOOKASSA_ENABLED=true
YOOKASSA_SHOP_ID=ВАШ_SHOP_ID
YOOKASSA_SECRET_KEY=ВАШ_SECRET

# CryptoBot
CRYPTOBOT_ENABLED=true
CRYPTOBOT_TOKEN=ВАШ_ТОКЕН

# Telegram Stars
TELEGRAM_STARS_ENABLED=true
```

После изменения: `cd /opt/bedolaga && docker compose restart bot`

---

## Следующие шаги после установки

1. **Напишите боту** `/start` в Telegram
2. **Создайте тарифы** в Remnawave Panel → Тарифы
3. **Подключите платёжную систему** в `/opt/bedolaga/.env`
4. **Настройте страницу подписки** (subscription-page) в Remnawave
5. **Создайте промокоды** через бот для тестирования

---

## Устранение неполадок

**Бот не стартует:**
```bash
cd /opt/bedolaga && docker compose logs --tail=50 bot
```

**Вебхук не работает:**
```bash
# Проверить что бот доступен из Remnawave
docker exec remnawave curl -s http://remnawave_bot:8080/health
```

**Бот не принимает платежи:**
```bash
grep -E 'ENABLED=true' /opt/bedolaga/.env | grep -v '#'
```

**Сбросить и переустановить:**
```bash
cd /opt/bedolaga && docker compose down --volumes
rm -rf /opt/bedolaga
bedolaga
```
