#!/usr/bin/env python3
"""
sim_topics.py — симуляция ВСЕХ внутренних уведомлений Bedolaga.
Запуск: docker exec remnawave_bot python /tmp/sim_topics.py

Маршрутизация (ваша конфигурация):
  Топик 2   → покупки, продления, триалы, баланс, докупки, промо, партнёры
  Топик 4   → CRM-биллинг, сервис, ошибки, подозрительный трафик
  Топик 441 → статусы ноды (создание/изменение/удаление/включение/отключение)
  Топик 6   → трафик ноды, ежедневные/недельные отчёты
  Топик 11  → тикеты поддержки
  Топик 13  → бекапы, ротация логов

NOTE: Bedolaga объединяет node+CRM+service в категорию INFRASTRUCTURE.
Разделение 441/4/6 для нод — через ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID=441
плюс ручная маршрутизация в этом симуляторе.
"""
import asyncio
import sys

sys.path.insert(0, '/app')

from aiogram import Bot
from aiogram.client.default import DefaultBotProperties
from app.config import settings
from app.services.admin_notification_service import AdminNotificationService, NotificationCategory

G = '\033[92m'; Y = '\033[93m'; R = '\033[91m'; C = '\033[96m'; B = '\033[1m'; N = '\033[0m'

ok     = lambda s: print(f'  {G}✓{N} {s}')
skip   = lambda s: print(f'  {Y}⚠{N} {s}')
fail   = lambda s: print(f'  {R}✗{N} {s}')
banner = lambda s: print(f'\n{B}━━━ {s} ━━━{N}')

NOW      = '24.06.2026 10:00'
USER     = 'Test User'
TG_ID    = str(settings.ADMIN_IDS[0]) if getattr(settings, 'ADMIN_IDS', None) else '467308835'
USERNAME = 'fnoup'
TAG      = '\n\n<i>#bedolaga</i>'  # метка источника

ADMIN_CHAT   = getattr(settings, 'ADMIN_NOTIFICATIONS_CHAT_ID', None)
# Топики по вашей конфигурации
T_GENERAL    = getattr(settings, 'ADMIN_NOTIFICATIONS_PURCHASES_TOPIC_ID', 2)
T_INFRA      = getattr(settings, 'ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID', 4)
T_NODE       = 441    # node created/modified/disabled/enabled/deleted
T_TRAFFIC    = getattr(settings, 'ADMIN_REPORTS_TOPIC_ID', 6)   # node.traffic_notify
T_REPORTS    = getattr(settings, 'ADMIN_REPORTS_TOPIC_ID', 6)   # ежедневные отчёты
T_TICKETS    = getattr(settings, 'ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID', 11)
T_BACKUP     = getattr(settings, 'BACKUP_SEND_TOPIC_ID', 13)
BACKUP_CHAT  = getattr(settings, 'BACKUP_SEND_CHAT_ID', ADMIN_CHAT)
REPORTS_CHAT = getattr(settings, 'ADMIN_REPORTS_CHAT_ID', ADMIN_CHAT)


async def snd(svc: AdminNotificationService, label: str, cat: NotificationCategory, text: str) -> None:
    try:
        ok_ = await svc.send_admin_notification(text + TAG, category=cat)
        (ok if ok_ else skip)(f'[{label}]')
    except Exception as e:
        fail(f'[{label}] — {e}')


async def snd_d(bot: Bot, label: str, chat, topic, text: str) -> None:
    if not chat:
        skip(f'[{label}] — chat_id не задан')
        return
    try:
        kw = {'chat_id': chat, 'text': text + TAG, 'parse_mode': 'HTML'}
        if topic:
            kw['message_thread_id'] = int(topic)
        await bot.send_message(**kw)
        ok(f'[{label}]')
    except Exception as e:
        fail(f'[{label}] — {e}')


async def main() -> None:
    bot = Bot(token=settings.BOT_TOKEN, default=DefaultBotProperties(parse_mode='HTML'))
    svc = AdminNotificationService(bot)

    print(f'{B}Симуляция уведомлений Bedolaga — все топики{N}')
    print(f'{C}→{N} Чат: {ADMIN_CHAT}')
    print(f'{C}→{N} Топики: 2=покупки | 4=CRM/сервис/ошибки | 441=ноды | 6=трафик/отчёты | 11=тикеты | 13=бекапы')

    # ── ТОПИК 441: СТАТУСЫ НОДЫ ────────────────────────────────────────────────
    banner('ТОПИК 441 — СТАТУСЫ НОДЫ (node created/modified/disabled/enabled/deleted)')
    NODE = ('France-01', 'fr1.vpn.example.com', '443')

    await snd_d(bot, 'node.connection_lost', ADMIN_CHAT, T_NODE,
        f'🚨 <b>Потеряно соединение с нодой</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>')
    await snd_d(bot, 'node.connection_restored', ADMIN_CHAT, T_NODE,
        f'✅ <b>Соединение с нодой восстановлено</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>')
    await snd_d(bot, 'node.created', ADMIN_CHAT, T_NODE,
        f'🟢 <b>Нода создана</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\nПорт: <code>{NODE[2]}</code>')
    await snd_d(bot, 'node.modified', ADMIN_CHAT, T_NODE,
        f'🔧 <b>Нода изменена</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\nПорт: <code>{NODE[2]}</code>')
    await snd_d(bot, 'node.disabled', ADMIN_CHAT, T_NODE,
        f'🔴 <b>Нода отключена</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\nПорт: <code>{NODE[2]}</code>')
    await snd_d(bot, 'node.enabled', ADMIN_CHAT, T_NODE,
        f'🟢 <b>Нода включена</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\nПорт: <code>{NODE[2]}</code>')
    await snd_d(bot, 'node.deleted', ADMIN_CHAT, T_NODE,
        f'🗑️ <b>Нода удалена</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\nПорт: <code>{NODE[2]}</code>')

    # ── ТОПИК 6: ТРАФИК НОДЫ ──────────────────────────────────────────────────
    banner('ТОПИК 6 — ТРАФИК НОДЫ (node.traffic_notify)')

    await snd_d(bot, 'node.traffic_notify', ADMIN_CHAT, T_TRAFFIC,
        f'📊 <b>Уведомление о трафике ноды</b>\nИмя: <code>{NODE[0]}</code>\nАдрес: <code>{NODE[1]}</code>\n\n'
        f'📊 Использовано: <b>1.00 ТБ</b> / 10.00 ТБ\n'
        f'📈 Загрузка: <b>10%</b>')

    # ── ТОПИК 4: CRM / СЕРВИС / ОШИБКИ ────────────────────────────────────────
    banner('ТОПИК 4 — СЕРВИС (service.*)')

    await snd(svc, 'service.panel_started', NotificationCategory.INFRASTRUCTURE,
        '🚀 <b>Панель RemnaWave запущена</b>\nВерсия: <code>1.0.0</code>\nПричина: scheduled restart')
    await snd(svc, 'service.login_attempt_success', NotificationCategory.INFRASTRUCTURE,
        '🔓 <b>Успешный вход в панель</b>\nПользователь: <code>admin</code>\nIP: <code>192.168.1.100</code>')
    await snd(svc, 'service.login_attempt_failed', NotificationCategory.INFRASTRUCTURE,
        '🔐 <b>Неудачная попытка входа в панель</b>\nIP: <code>192.168.1.200</code>\nUser-Agent: <code>curl/7.88</code>')
    await snd(svc, 'service.subpage_config_changed', NotificationCategory.INFRASTRUCTURE,
        '📄 <b>Конфиг страницы подписки изменён</b>')

    banner('ТОПИК 4 — CRM БИЛЛИНГ (crm.*)')

    for title in [
        '💳 Оплата ноды через 7 дней',
        '💳 Оплата ноды через 48 часов',
        '⚠️ Оплата ноды через 24 часа',
        '🔴 Оплата ноды сегодня',
        '❗ Просрочка оплаты ноды: 24 часа',
        '❗ Просрочка оплаты ноды: 48 часов',
        '🚨 Просрочка оплаты ноды: 7 дней',
    ]:
        await snd(svc, title, NotificationCategory.INFRASTRUCTURE,
            f'{title}\nНода: <code>{NODE[0]}</code>\nСумма: <code>1500 RUB</code>')

    banner('ТОПИК 4 — ОШИБКИ И СИСТЕМА (errors.*)')

    await snd(svc, 'errors.bandwidth_max_notifications', NotificationCategory.ERRORS,
        '⚠️ <b>Достигнут лимит уведомлений о трафике</b>\nПользователей с лимитом: <code>5</code>')
    await snd(svc, 'Обновление версии бота', NotificationCategory.INFRASTRUCTURE,
        f'🔄 <b>Доступна новая версия бота</b>\n\nТекущая: <code>3.61.0</code>\nНовая: <code>3.62.0</code>\n\n'
        f'Обновите командой: <code>bedolaga</code>')
    await snd(svc, 'Ошибка проверки версии', NotificationCategory.ERRORS,
        '⚠️ <b>Ошибка проверки обновлений</b>\n\nНе удалось подключиться к GitHub API.\nТекущая версия: <code>3.61.0</code>')
    await snd(svc, 'Техническое обслуживание включено', NotificationCategory.INFRASTRUCTURE,
        '🔧 <b>Режим обслуживания ВКЛЮЧЁН</b>\n\nПричина: автоотключение при ошибках\nВремя: <code>24.06.2026 10:00</code>')

    # ── ТОПИК 2: ПОКУПКИ ──────────────────────────────────────────────────────
    banner('ТОПИК 2 — ПОКУПКИ (PURCHASES)')

    await snd(svc, 'Покупка подписки', NotificationCategory.PURCHASES, f"""🛒 <b>НОВАЯ ПОКУПКА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}
👥 <b>Статус:</b> 🆕 Новый

📦 <b>Тариф:</b> Стандартный
📅 <b>Период:</b> 30 дней
💰 <b>Сумма:</b> 990₽
💳 <b>Способ:</b> YooKassa
🔑 <b>ID платежа:</b> <code>pay_001</code>

📆 <b>Действует до:</b> 24.07.2026
🌐 <b>Сервер:</b> {NODE[0]}

⏰ <i>{NOW}</i>""")

    await snd(svc, 'Покупка с лендинга', NotificationCategory.PURCHASES, f"""🛒 <b>ПОКУПКА С ЛЕНДИНГА</b>

🌐 Страница: <b>/buy/standard</b>
📧 Покупатель: <code>test@example.com</code>

<blockquote>🏷️ Тариф: <b>Стандартный</b>
📅 Период: 30 дн.
💵 <b>990₽</b> • YooKassa
🆔 pay_002</blockquote>

<i>{NOW}</i>""")

    banner('ТОПИК 2 — ПРОДЛЕНИЯ (RENEWALS)')

    await snd(svc, 'Продление подписки', NotificationCategory.RENEWALS, f"""🔄 <b>ПРОДЛЕНИЕ ПОДПИСКИ</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}

📦 <b>Тариф:</b> Стандартный
📅 <b>Продлено на:</b> 30 дней
💰 <b>Сумма:</b> 990₽
💳 <b>Способ:</b> YooKassa

📆 <b>Новая дата окончания:</b> 24.07.2026
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Автопродление с баланса', NotificationCategory.RENEWALS, f"""🔄 <b>АВТОПРОДЛЕНИЕ</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})

📦 <b>Тариф:</b> Стандартный / 30 дн.
💰 <b>Списано с баланса:</b> 990₽
🏦 <b>Остаток:</b> 0₽

📆 <b>Новая дата окончания:</b> 24.07.2026
⏰ <i>{NOW}</i>""")

    banner('ТОПИК 2 — ТРИАЛЫ (TRIALS)')

    await snd(svc, 'Активация триала', NotificationCategory.TRIALS, f"""🎯 <b>АКТИВАЦИЯ ТРИАЛА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}
👥 <b>Статус:</b> 🆕 Новый
🏷️ <b>Промогруппа:</b> —

⏰ <b>Параметры:</b>
📅 Период: 3 дней
📊 Трафик: 5.00 ГБ
📱 Устройства: 1
🌐 Сервер: {NODE[0]}

📆 <b>Действует до:</b> 27.06.2026 10:00
⏰ <i>{NOW}</i>""")

    banner('ТОПИК 2 — БАЛАНС (BALANCE)')

    await snd(svc, 'Пополнение баланса', NotificationCategory.BALANCE, f"""💰 <b>ПОПОЛНЕНИЕ БАЛАНСА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}

💳 <b>Способ:</b> YooKassa
💰 <b>Сумма:</b> 990₽
🏦 <b>Новый баланс:</b> 990₽
🔑 <b>ID:</b> <code>pay_003</code>
⏰ <i>{NOW}</i>""")

    banner('ТОПИК 2 — ДОПОЛНЕНИЯ (ADDONS)')

    await snd(svc, 'Докупка трафика', NotificationCategory.ADDONS, f"""📦 <b>ДОКУПКА ТРАФИКА</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})

📊 <b>Добавлено:</b> 50 ГБ
💰 <b>Сумма:</b> 300₽
📊 <b>Новый лимит:</b> 150 ГБ
⏰ <i>{NOW}</i>""")

    banner('ТОПИК 2 — ПРОМО (PROMO)')

    await snd(svc, 'Промокод применён', NotificationCategory.PROMO, f"""🎟 <b>ПРОМОКОД ПРИМЕНЁН</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})

🎟 <b>Промокод:</b> <code>TESTPROMO</code>
💎 <b>Тип:</b> Скидка 20%
📦 <b>Тариф:</b> Стандартный
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Переход по кампании', NotificationCategory.PROMO, f"""🔗 <b>ПЕРЕХОД ПО КАМПАНИИ</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})
🌐 <b>Кампания:</b> summer2026 / <b>Переходов:</b> 42
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Регистрация по кампании', NotificationCategory.PROMO, f"""🎉 <b>РЕГИСТРАЦИЯ ПО КАМПАНИИ</b>

👤 <b>Новый:</b> {USER} (@{USERNAME})
🌐 <b>Кампания:</b> summer2026
🔗 <b>Реферер:</b> @partner_user
⏰ <i>{NOW}</i>""")

    banner('ТОПИК 2 — ПАРТНЁРЫ (PARTNERS)')

    await snd(svc, 'Партнёрская заявка', NotificationCategory.PARTNERS, f"""🤝 <b>НОВАЯ ПАРТНЁРСКАЯ ЗАЯВКА</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})
📧 <b>Email:</b> partner@example.com
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Запрос на вывод', NotificationCategory.PARTNERS, f"""💸 <b>ЗАПРОС НА ВЫВОД СРЕДСТВ</b>

👤 <b>Партнёр:</b> {USER} (@{USERNAME})
💰 <b>Сумма:</b> 5 000₽
💳 <b>Реквизиты:</b> 4111 **** **** 1111
📝 <b>Заявка #1</b>
⏰ <i>{NOW}</i>""")

    # ── ТОПИК 6: ЕЖЕДНЕВНЫЕ ОТЧЁТЫ ────────────────────────────────────────────
    banner('ТОПИК 6 — ЕЖЕДНЕВНЫЕ / НЕДЕЛЬНЫЕ ОТЧЁТЫ (ADMIN_REPORTS)')

    await snd_d(bot, 'Ежедневный отчёт', REPORTS_CHAT, T_REPORTS, f"""📊 <b>Отчет за вчера, 23.06.2026</b>

🧭 <b>Итог по периоду</b>
• Новых пользователей: <b>3</b>
• Новых триалов: <b>2</b>
• Конверсий триал → платная: <b>1</b> (<i>50.0%</i>)
• Новых платных: <b>1</b>
• Поступления (пополнения): <b>990₽</b>

💎 <b>Подписки</b>
• Активные триалы: 1
• Активные платные: 1

💰 <b>Финансы</b>
• Оплаты: 1 на сумму 990₽
• Пополнения: 0 на сумму 0₽

👥 <b>Пользователи</b>
• Всего в базе: 4 / Активных: 2 / Без подписки: 2""")

    await snd_d(bot, 'Недельный отчёт', REPORTS_CHAT, T_REPORTS, f"""📊 <b>Отчет за период 17.06 – 23.06.2026</b>

🧭 <b>Итог</b>
• Новых пользователей: <b>12</b>
• Триалов: <b>8</b> / Конверсий: <b>4</b> (<i>50%</i>)
• Платных: <b>6</b>
• Поступления: <b>5 940₽</b>

💰 Оплаты: 6 × 990₽ = 5 940₽""")

    # ── ТОПИК 11: ТИКЕТЫ ──────────────────────────────────────────────────────
    banner('ТОПИК 11 — ТИКЕТЫ (TICKETS)')

    await snd(svc, 'Новый тикет #1', NotificationCategory.TICKETS, f"""🎫 <b>НОВЫЙ ТИКЕТ #1</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}

💬 <i>Не работает подключение на iPhone 15. Пробовал переустановить профиль — не помогает.</i>
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Ответ пользователя в тикете', NotificationCategory.TICKETS, f"""💬 <b>ОТВЕТ В ТИКЕТЕ #1</b>

👤 {USER} (@{USERNAME})
<i>Спасибо, всё заработало!</i>
⏰ <i>{NOW}</i>""")

    await snd(svc, 'SLA нарушен (60 мин без ответа)', NotificationCategory.TICKETS, f"""⏰ <b>SLA НАРУШЕН — ТИКЕТ #1</b>

👤 {USER} (@{USERNAME})
⏱ <b>Без ответа:</b> 60 минут
💬 <i>Не работает подключение на iPhone 15.</i>
⚠️ Тикет требует немедленного внимания!
⏰ <i>{NOW}</i>""")

    # ── ТОПИК 13: БЕКАПЫ И ЛОГИ ───────────────────────────────────────────────
    banner('ТОПИК 13 — БЕКАПЫ (BACKUP) + РОТАЦИЯ ЛОГОВ')

    await snd_d(bot, 'Бекап создан', BACKUP_CHAT, T_BACKUP, f"""💾 <b>БЕКАП СОЗДАН</b>

✅ База данных сохранена
📁 <code>backup_2026-06-24_01-00.tar.gz</code>
📊 Размер: 2.4 МБ | Сжатие: вкл | Логи: вкл
🗂 Всего: 7 бекапов
⏰ <i>{NOW}</i>""")

    await snd_d(bot, 'Ошибка бекапа', BACKUP_CHAT, T_BACKUP, f"""❌ <b>ОШИБКА БЕКАПА</b>

⚠️ Не удалось создать резервную копию
🔍 <b>Причина:</b> <code>No space left on device</code>
📂 /app/data/backups
🔧 Проверь свободное место!
⏰ <i>{NOW}</i>""")

    # Ошибка бекапа дублируется в топик 4 (ERRORS)
    await snd(svc, 'Ошибка бекапа (дубль → топик 4)', NotificationCategory.ERRORS, f"""❌ <b>ОШИБКА БЕКАПА</b>

⚠️ Не удалось создать резервную копию
🔍 <b>Причина:</b> <code>No space left on device</code>
📂 /app/data/backups
⏰ <i>{NOW}</i>""")

    await snd_d(bot, 'Ротация логов', BACKUP_CHAT, T_BACKUP, f"""📋 <b>РОТАЦИЯ ЛОГОВ</b>

✅ Логи обработаны
📁 <code>logs_2026-06-24_00-00.tar.gz</code>
📊 Архив: 1.1 МБ | Удалено: 3 файла (старше 7 дней)
⏰ <i>{NOW}</i>""")

    # ── ИТОГ ─────────────────────────────────────────────────────────────────
    print(f'\n{G}{B}Готово!{N}')
    print(f'  Топик 441  → ноды (создание/изменение/удаление/вкл/выкл/разрыв)')
    print(f'  Топик 6    → трафик ноды + ежедневные/недельные отчёты')
    print(f'  Топик 4    → CRM-биллинг, сервис, ошибки (+ дубль backup-ошибок)')
    print(f'  Топик 2    → покупки, продления, триалы, баланс, промо, партнёры')
    print(f'  Топик 11   → тикеты поддержки')
    print(f'  Топик 13   → бекапы + ротация логов')
    print(f'  {C}Все помечены #bedolaga{N}')

    await bot.session.close()


if __name__ == '__main__':
    asyncio.run(main())
