#!/usr/bin/env python3
"""
sim_topics.py — симуляция ВСЕХ внутренних уведомлений Bedolaga.
Запуск: docker exec remnawave_bot python /tmp/sim_topics.py

Маршрутизация:
  Топик 2   → покупки, продления, триалы, баланс, докупки, промо, партнёры
  Топик 4   → CRM-биллинг, сервис, ошибки (+ дубль backup-ошибок)
  Топик 441 → статусы ноды (создание/изменение/удаление/вкл/выкл)
  Топик 6   → трафик ноды, ежедневные/недельные отчёты
  Топик 11  → тикеты поддержки
  Топик 13  → бекапы, ротация логов, обновление TLS
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

NOW       = '24.06.2026 12:00'
USER      = 'Алексей М.'
TG_ID     = str(settings.ADMIN_IDS[0]) if getattr(settings, 'ADMIN_IDS', None) else '100000000'
USERNAME  = 'user_example'
TAG       = '\n\n<i>#bedolaga</i>'

ADMIN_CHAT   = getattr(settings, 'ADMIN_NOTIFICATIONS_CHAT_ID', None)
BACKUP_CHAT  = getattr(settings, 'BACKUP_SEND_CHAT_ID', ADMIN_CHAT)
REPORTS_CHAT = getattr(settings, 'ADMIN_REPORTS_CHAT_ID', ADMIN_CHAT)

# Топики по конфигурации (ADMIN_NOTIFICATIONS_*_TOPIC_ID из .env)
T_GENERAL = getattr(settings, 'ADMIN_NOTIFICATIONS_PURCHASES_TOPIC_ID', 2)
T_INFRA   = getattr(settings, 'ADMIN_NOTIFICATIONS_INFRASTRUCTURE_TOPIC_ID', 4)  # CRM/сервис/ошибки
T_NODE    = 441    # node-статусы — хардкод (отдельного ключа в Bedolaga нет)
T_TRAFFIC = getattr(settings, 'ADMIN_REPORTS_TOPIC_ID', 6)
T_REPORTS = getattr(settings, 'ADMIN_REPORTS_TOPIC_ID', 6)
T_TICKETS = getattr(settings, 'ADMIN_NOTIFICATIONS_TICKET_TOPIC_ID', 11)
T_BACKUP  = getattr(settings, 'BACKUP_SEND_TOPIC_ID', 13)


async def snd(svc: AdminNotificationService, label: str, cat: NotificationCategory, text: str) -> None:
    """Отправляет через AdminNotificationService (категорийная маршрутизация из .env)."""
    try:
        result = await svc.send_admin_notification(text + TAG, category=cat)
        (ok if result else skip)(f'[{label}]')
    except Exception as e:
        fail(f'[{label}] — {e}')


async def snd_d(bot: Bot, label: str, chat, topic, text: str) -> None:
    """Отправляет напрямую в конкретный chat+topic (обход категорийной маршрутизации)."""
    if not chat:
        skip(f'[{label}] — CHAT_ID не задан в .env')
        return
    try:
        kwargs = {'chat_id': chat, 'text': text + TAG, 'parse_mode': 'HTML'}
        if topic:
            kwargs['message_thread_id'] = int(topic)
        await bot.send_message(**kwargs)
        ok(f'[{label}]')
    except Exception as e:
        fail(f'[{label}] — {e}')


async def main() -> None:
    bot = Bot(token=settings.BOT_TOKEN, default=DefaultBotProperties(parse_mode='HTML'))
    svc = AdminNotificationService(bot)

    print(f'{B}Симуляция уведомлений Bedolaga — все топики{N}')
    print(f'{C}→{N} Чат: {ADMIN_CHAT}')
    print(f'{C}→{N} 441=ноды | {T_INFRA}=CRM/сервис/ошибки | {T_TRAFFIC}=отчёты/трафик | {T_TICKETS}=тикеты | {T_BACKUP}=бекапы')

    NODE = ('France-01', 'fr1.vpn.example.com', '443')

    # ── ТОПИК 441: СТАТУСЫ НОДЫ ────────────────────────────────────────────────
    banner('ТОПИК 441 — СТАТУСЫ НОДЫ')

    await snd_d(bot, 'node.connection_lost', ADMIN_CHAT, T_NODE,
        f'🚨 <b>Потеряно соединение с нодой</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.connection_restored', ADMIN_CHAT, T_NODE,
        f'✅ <b>Соединение с нодой восстановлено</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'Время простоя: <code>2 мин 14 сек</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.created', ADMIN_CHAT, T_NODE,
        f'🟢 <b>Нода создана</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'Порт: <code>{NODE[2]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.modified', ADMIN_CHAT, T_NODE,
        f'🔧 <b>Нода изменена</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'Порт: <code>{NODE[2]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.disabled', ADMIN_CHAT, T_NODE,
        f'🔴 <b>Нода отключена</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.enabled', ADMIN_CHAT, T_NODE,
        f'🟢 <b>Нода включена</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'node.deleted', ADMIN_CHAT, T_NODE,
        f'🗑️ <b>Нода удалена</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n'
        f'⏰ <i>{NOW}</i>')

    # ── ТОПИК 6: ТРАФИК НОДЫ ──────────────────────────────────────────────────
    banner(f'ТОПИК {T_TRAFFIC} — ТРАФИК НОДЫ')

    await snd_d(bot, 'node.traffic_notify', ADMIN_CHAT, T_TRAFFIC,
        f'📊 <b>Уведомление о трафике ноды</b>\n'
        f'Имя: <code>{NODE[0]}</code>\n'
        f'Адрес: <code>{NODE[1]}</code>\n\n'
        f'📈 Использовано: <b>1.00 ТБ</b> / 10.00 ТБ\n'
        f'📉 Загрузка: <b>10%</b>\n'
        f'⏰ <i>{NOW}</i>')

    # ── ТОПИК 4: СЕРВИС / CRM / ОШИБКИ ────────────────────────────────────────
    banner(f'ТОПИК {T_INFRA} — СЕРВИС (service.*)')

    await snd(svc, 'service.panel_started', NotificationCategory.INFRASTRUCTURE,
        '🚀 <b>Панель RemnaWave запущена</b>\n'
        'Версия: <code>2.1.0</code>\n'
        'Причина: <code>scheduled restart</code>')

    await snd(svc, 'service.login_attempt_success', NotificationCategory.INFRASTRUCTURE,
        '🔓 <b>Успешный вход в панель</b>\n'
        'IP: <code>85.208.72.14</code>\n'
        'User-Agent: <code>Mozilla/5.0 (Windows NT 10.0; Win64)</code>')

    await snd(svc, 'service.login_attempt_failed', NotificationCategory.INFRASTRUCTURE,
        '🔐 <b>Неудачная попытка входа в панель</b>\n'
        'IP: <code>185.220.101.47</code>\n'
        'User-Agent: <code>curl/8.1.0</code>\n'
        '⚠️ Проверьте, не брутфорс ли это')

    await snd(svc, 'service.subpage_config_changed', NotificationCategory.INFRASTRUCTURE,
        '📄 <b>Конфиг страницы подписки изменён</b>\n'
        'Изменения вступят в силу при следующем обращении')

    banner(f'ТОПИК {T_INFRA} — CRM БИЛЛИНГ (crm.*)')

    crm_events = [
        ('crm.payment_in_7_days',      '💳', 'Оплата ноды через 7 дней'),
        ('crm.payment_in_48hrs',        '💳', 'Оплата ноды через 48 часов'),
        ('crm.payment_in_24hrs',        '⚠️', 'Оплата ноды через 24 часа'),
        ('crm.payment_due_today',       '🔴', 'Оплата ноды сегодня'),
        ('crm.payment_overdue_24hrs',   '❗', 'Просрочка оплаты: 24 часа'),
        ('crm.payment_overdue_48hrs',   '❗', 'Просрочка оплаты: 48 часов'),
        ('crm.payment_overdue_7_days',  '🚨', 'Просрочка оплаты: 7 дней'),
    ]
    for label, icon, title in crm_events:
        await snd(svc, label, NotificationCategory.INFRASTRUCTURE,
            f'{icon} <b>{title}</b>\n'
            f'Нода: <code>{NODE[0]}</code> ({NODE[1]})\n'
            f'Сумма: <b>1 500 ₽</b>')

    banner(f'ТОПИК {T_INFRA} — ОШИБКИ И СИСТЕМА')

    await snd(svc, 'errors.bandwidth_max_notifications', NotificationCategory.ERRORS,
        '⚠️ <b>Лимит уведомлений о трафике</b>\n'
        'Пользователей в очереди: <code>5</code>\n'
        'Следующие уведомления заблокированы до сброса')

    await snd(svc, 'Доступна новая версия бота', NotificationCategory.INFRASTRUCTURE,
        '🔄 <b>Доступна новая версия Bedolaga</b>\n\n'
        'Текущая: <code>3.61.0</code>\n'
        'Новая: <code>3.62.0</code>\n\n'
        'Обновите командой:\n<code>bedolaga</code>')

    await snd(svc, 'Ошибка проверки версии', NotificationCategory.ERRORS,
        '⚠️ <b>Ошибка проверки обновлений</b>\n'
        'Не удалось подключиться к GitHub API.\n'
        'Текущая версия: <code>3.61.0</code>')

    await snd(svc, 'Режим обслуживания включён', NotificationCategory.INFRASTRUCTURE,
        '🔧 <b>Режим обслуживания ВКЛЮЧЁН</b>\n\n'
        'Причина: автоотключение при ошибках\n'
        f'Время: <code>{NOW}</code>')

    # ── ТОПИК 2: ПОКУПКИ ──────────────────────────────────────────────────────
    banner(f'ТОПИК {T_GENERAL} — ПОКУПКИ (PURCHASES)')

    await snd(svc, 'Покупка подписки', NotificationCategory.PURCHASES, f"""🛒 <b>НОВАЯ ПОКУПКА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}
👥 <b>Статус:</b> 🆕 Новый

📦 <b>Тариф:</b> Стандартный
📅 <b>Период:</b> 30 дней
💰 <b>Сумма:</b> 990₽
💳 <b>Способ оплаты:</b> YooKassa
🔑 <b>ID платежа:</b> <code>2e7a2db5-0004-5000-a000-1b68b2a44e55</code>

📆 <b>Действует до:</b> 24.07.2026
🌐 <b>Сервер:</b> {NODE[0]}
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Покупка с лендинга', NotificationCategory.PURCHASES, f"""🛒 <b>ПОКУПКА С ЛЕНДИНГА</b>

🌐 Страница: <b>/buy/standard</b>
📧 Покупатель: <code>user@example.com</code>

<blockquote>🏷️ Тариф: <b>Стандартный</b>
📅 Период: 30 дней
💵 <b>990₽</b> • YooKassa
🔑 2e7a2db5-0005-5000-a000-1b68b2a44e66</blockquote>

⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — ПРОДЛЕНИЯ (RENEWALS)')

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

📦 <b>Тариф:</b> Стандартный / 30 дней
💰 <b>Списано с баланса:</b> 990₽
🏦 <b>Остаток баланса:</b> 10₽

📆 <b>Новая дата окончания:</b> 24.07.2026
⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — ТРИАЛЫ (TRIALS)')

    await snd(svc, 'Активация триала', NotificationCategory.TRIALS, f"""🎯 <b>АКТИВАЦИЯ ТРИАЛА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}
👥 <b>Статус:</b> 🆕 Новый
🏷️ <b>Промогруппа:</b> —

⚙️ <b>Параметры триала:</b>
📅 Период: 3 дня
📊 Трафик: 5.00 ГБ
📱 Устройства: 1
🌐 Сервер: {NODE[0]}

📆 <b>Действует до:</b> 27.06.2026 12:00
⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — БАЛАНС (BALANCE)')

    await snd(svc, 'Пополнение баланса', NotificationCategory.BALANCE, f"""💰 <b>ПОПОЛНЕНИЕ БАЛАНСА</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}

💳 <b>Способ:</b> YooKassa
💰 <b>Сумма пополнения:</b> 1 000₽
🏦 <b>Новый баланс:</b> 1 010₽
🔑 <b>ID транзакции:</b> <code>2e7a2db5-0006-5000-a000-1b68b2a44e77</code>
⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — ДОПОЛНЕНИЯ (ADDONS)')

    await snd(svc, 'Докупка трафика', NotificationCategory.ADDONS, f"""📦 <b>ДОКУПКА ТРАФИКА</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})

📊 <b>Добавлено трафика:</b> +50 ГБ
💰 <b>Сумма:</b> 300₽
📊 <b>Новый лимит:</b> 150 ГБ
⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — ПРОМО (PROMO)')

    await snd(svc, 'Промокод применён', NotificationCategory.PROMO, f"""🎟 <b>ПРОМОКОД ПРИМЕНЁН</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})

🎟 <b>Промокод:</b> <code>SUMMER2026</code>
💎 <b>Тип скидки:</b> 20% на первую оплату
📦 <b>Тариф:</b> Стандартный / 30 дней
💰 <b>Итоговая сумма:</b> 792₽ (было 990₽)
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Переход по кампании', NotificationCategory.PROMO, f"""🔗 <b>ПЕРЕХОД ПО UTM-КАМПАНИИ</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})
🌐 <b>Кампания:</b> <code>summer2026</code>
📊 <b>Всего переходов по кампании:</b> 42
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Регистрация по кампании', NotificationCategory.PROMO, f"""🎉 <b>РЕГИСТРАЦИЯ ПО КАМПАНИИ</b>

👤 <b>Новый пользователь:</b> {USER} (@{USERNAME})
🌐 <b>Кампания:</b> <code>summer2026</code>
🔗 <b>Реферер:</b> @partner_user
⏰ <i>{NOW}</i>""")

    banner(f'ТОПИК {T_GENERAL} — ПАРТНЁРЫ (PARTNERS)')

    await snd(svc, 'Партнёрская заявка', NotificationCategory.PARTNERS, f"""🤝 <b>НОВАЯ ПАРТНЁРСКАЯ ЗАЯВКА</b>

👤 <b>Пользователь:</b> {USER} (@{USERNAME})
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📧 <b>Email:</b> partner@example.com
🏦 <b>Реквизиты для вывода:</b> указаны
⏰ <i>{NOW}</i>""")

    await snd(svc, 'Запрос на вывод', NotificationCategory.PARTNERS, f"""💸 <b>ЗАПРОС НА ВЫВОД СРЕДСТВ</b>

👤 <b>Партнёр:</b> {USER} (@{USERNAME})
💰 <b>Сумма запроса:</b> 5 000₽
💳 <b>Реквизиты:</b> СБП / Тинькофф
📝 <b>Заявка #7</b>
⏰ <i>{NOW}</i>""")

    # ── ТОПИК 6: ОТЧЁТЫ ───────────────────────────────────────────────────────
    banner(f'ТОПИК {T_REPORTS} — ЕЖЕДНЕВНЫЕ / НЕДЕЛЬНЫЕ ОТЧЁТЫ')

    await snd_d(bot, 'Ежедневный отчёт', REPORTS_CHAT, T_REPORTS, f"""📊 <b>Отчёт за вчера, 23.06.2026</b>

🧭 <b>Итог дня</b>
• Новых пользователей: <b>5</b>
• Новых триалов: <b>3</b>
• Конверсий триал → платная: <b>2</b> (<i>66.7%</i>)
• Новых платных: <b>3</b>
• Поступления: <b>2 970₽</b>

💎 <b>Активные подписки</b>
• Триалы: 4
• Платные: 12

💰 <b>Финансы дня</b>
• Оплат: 3 на сумму 2 970₽
• Пополнений баланса: 1 на сумму 1 000₽

👥 <b>База пользователей</b>
• Всего: 48 / Активных: 16 / Без подписки: 32""")

    await snd_d(bot, 'Недельный отчёт', REPORTS_CHAT, T_REPORTS, f"""📊 <b>Отчёт за период 17.06 – 23.06.2026</b>

🧭 <b>Итог недели</b>
• Новых пользователей: <b>28</b>
• Триалов: <b>19</b> / Конверсий: <b>9</b> (<i>47.4%</i>)
• Новых платных: <b>15</b>
• Поступления: <b>18 810₽</b>

💰 Оплат: 15 × 990₽ + 3 × 1 980₽ = 20 730₽
🔄 Автопродлений: 3 × 990₽ = 2 970₽""")

    # ── ТОПИК 11: ТИКЕТЫ ──────────────────────────────────────────────────────
    banner(f'ТОПИК {T_TICKETS} — ТИКЕТЫ (TICKETS)')

    await snd(svc, 'Новый тикет #42', NotificationCategory.TICKETS, f"""🎫 <b>НОВЫЙ ТИКЕТ #42</b>

👤 <b>Пользователь:</b> {USER}
🆔 <b>Telegram ID:</b> <code>{TG_ID}</code>
📱 <b>Username:</b> @{USERNAME}

💬 <i>Не работает подключение на iPhone 15 Pro. Пробовал переустановить профиль — не помогает. Последний раз работало вчера.</i>

⏰ Открыт: <i>{NOW}</i>""")

    await snd(svc, 'Ответ пользователя в тикете', NotificationCategory.TICKETS, f"""💬 <b>ОТВЕТ В ТИКЕТЕ #42</b>

👤 {USER} (@{USERNAME})
<i>Спасибо, помогло! После сброса настроек и нового импорта всё заработало.</i>
⏰ <i>{NOW}</i>""")

    await snd(svc, 'SLA нарушен (60 мин без ответа)', NotificationCategory.TICKETS, f"""⏰ <b>SLA НАРУШЕН — ТИКЕТ #42</b>

👤 {USER} (@{USERNAME})
⏱ <b>Ожидает ответа:</b> 60 минут
💬 <i>Не работает подключение на iPhone 15 Pro.</i>
⚠️ Требует немедленного ответа!""")

    # ── ТОПИК 13: БЕКАПЫ, ЛОГИ, TLS ──────────────────────────────────────────
    banner(f'ТОПИК {T_BACKUP} — БЕКАПЫ (BACKUP)')

    await snd_d(bot, 'Бекап создан', BACKUP_CHAT, T_BACKUP, f"""💾 <b>БЕКАП СОЗДАН</b>

✅ База данных сохранена
📁 <code>backup_2026-06-24_01-00.tar.gz</code>
📊 Размер: 2.4 МБ
⚙️ Сжатие: вкл | Логи: вкл
🗂 Хранится копий: 7 / 7
⏰ <i>01:00, 24.06.2026</i>""")

    await snd_d(bot, 'Ошибка бекапа (→ топик 13)', BACKUP_CHAT, T_BACKUP, f"""❌ <b>ОШИБКА БЕКАПА</b>

⚠️ Не удалось создать резервную копию
🔍 <b>Причина:</b> <code>No space left on device</code>
📂 Путь: <code>/app/data/backups</code>
🔧 <b>Действие:</b> Проверьте свободное место на диске
⏰ <i>{NOW}</i>""")

    # Ошибка бекапа дублируется в ERRORS (→ топик 4)
    await snd(svc, 'Ошибка бекапа (дубль → топик 4)', NotificationCategory.ERRORS,
        f'❌ <b>ОШИБКА БЕКАПА</b>\n\n'
        f'Не удалось создать резервную копию\n'
        f'Причина: <code>No space left on device</code>\n'
        f'📂 <code>/app/data/backups</code>\n'
        f'⏰ <i>{NOW}</i>')

    await snd_d(bot, 'Ротация логов', BACKUP_CHAT, T_BACKUP, f"""📋 <b>РОТАЦИЯ ЛОГОВ</b>

✅ Архивирование выполнено
📁 <code>logs_2026-06-24_00-00.tar.gz</code>
📊 Архив: 1.1 МБ
🗑 Удалено: 3 файла (старше 7 дней)
⏰ <i>00:00, 24.06.2026</i>""")

    await snd_d(bot, 'TLS-сертификат обновлён (certbot hook)', BACKUP_CHAT, T_BACKUP,
        '🔒 <b>TLS-сертификат обновлён</b>\n\n'
        '🌐 <b>Домены:</b>\n'
        '• <code>vpn.example.com</code>\n'
        '• <code>sub.vpn.example.com</code>\n\n'
        '📅 <b>Действует до:</b> <code>22.09.2026</code>\n'
        '📂 <b>Путь:</b> <code>/etc/letsencrypt/live/vpn.example.com</code>\n\n'
        '<i>#tls #certbot #bedolaga</i>')

    # ── ИТОГ ──────────────────────────────────────────────────────────────────
    print(f'\n{G}{B}Готово! Все уведомления отправлены.{N}')
    print(f'  Топик 441   → ноды (создание/изменение/удаление/вкл/выкл/разрыв)')
    print(f'  Топик 6     → трафик ноды + ежедневные/недельные отчёты')
    print(f'  Топик 4     → CRM-биллинг, сервис, ошибки (+ дубль backup-ошибок)')
    print(f'  Топик 2     → покупки, продления, триалы, баланс, промо, партнёры')
    print(f'  Топик 11    → тикеты поддержки')
    print(f'  Топик 13    → бекапы + ротация логов + обновление TLS')
    print(f'  {C}Все помечены #bedolaga{N}')

    await bot.session.close()


if __name__ == '__main__':
    asyncio.run(main())
