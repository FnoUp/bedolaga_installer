# -*- coding: utf-8 -*-
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable, ListFlowable, ListItem
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
import sys

# Кириллица: регистрируем системный шрифт с поддержкой юникода
pdfmetrics.registerFont(TTFont('Body', 'C:/Windows/Fonts/segoeui.ttf'))
pdfmetrics.registerFont(TTFont('BodyBold', 'C:/Windows/Fonts/segoeuib.ttf'))

BLUE = colors.HexColor('#0A66C2')
DARK = colors.HexColor('#1A1A1A')
GRAY = colors.HexColor('#6B6B6B')
GREEN = colors.HexColor('#1E9E5A')
LIGHT_BG = colors.HexColor('#F2F6FC')
LIGHT_GREEN = colors.HexColor('#EAF7EF')

styles = {
    'Title': ParagraphStyle('Title', fontName='BodyBold', fontSize=22, leading=28, textColor=BLUE, spaceAfter=8),
    'Subtitle': ParagraphStyle('Subtitle', fontName='Body', fontSize=11, leading=14, textColor=GRAY, spaceAfter=14),
    'H2': ParagraphStyle('H2', fontName='BodyBold', fontSize=13.5, textColor=DARK, spaceBefore=10, spaceAfter=5),
    'Body': ParagraphStyle('Body', fontName='Body', fontSize=9.5, textColor=DARK, leading=13),
    'BodySmall': ParagraphStyle('BodySmall', fontName='Body', fontSize=8.5, textColor=GRAY, leading=12),
    'Bullet': ParagraphStyle('Bullet', fontName='Body', fontSize=9.5, textColor=DARK, leading=14),
    'Code': ParagraphStyle('Code', fontName='Body', fontSize=8.5, textColor=DARK, leading=12,
                            backColor=LIGHT_BG, borderPadding=(4, 6, 4, 6)),
}

doc = SimpleDocTemplate(
    sys.argv[1] if len(sys.argv) > 1 else 'overview.pdf',
    pagesize=A4,
    topMargin=13 * mm, bottomMargin=11 * mm, leftMargin=16 * mm, rightMargin=16 * mm,
)

story = []

story.append(Paragraph('TorchVPN — обзор системы', styles['Title']))
story.append(Paragraph('Bedolaga (Telegram-бот) + Remnawave (VPN-панель) · обновлено 12.07.2026', styles['Subtitle']))
story.append(HRFlowable(width='100%', thickness=1, color=BLUE, spaceAfter=10))

story.append(Paragraph('Что это', styles['H2']))
story.append(Paragraph(
    'VPN-сервис на 5 серверах (панель + 4 ноды: Finland, Sweden, Moscow, Family). Продажами и '
    'поддержкой занимается Telegram-бот <b>Bedolaga</b>, доработанный под задачи проекта '
    '(форк, не оригинал автора — обновления автора можно безопасно подмерживать).',
    styles['Body']
))

story.append(Paragraph('Что уже работает', styles['H2']))
features = [
    '<b>Тарифы и промогруппы</b> — настраиваются через админ-панель бота (Telegram), без правки кода',
    '<b>Триал</b> — стандартный бесплатный период всем новым пользователям (группа Trial в Remnawave)',
    '<b>Оплата через поддержку</b> — юзер создаёт заявку (сумма или подписка) → тикет админам с кнопками '
    '«Подтвердить/Отклонить/Ответить» → баланс зачисляется или подписка активируется → тикет закрывается',
    '<b>Гайд «Как подключиться»</b> — кнопка в главном меню + автоотправка после первой покупки/триала: '
    'аннотированный скриншот приложения + статья с инструкцией (смена региона App Store и т.д.)',
    '<b>Уведомления по темам</b> — покупки/ноды/отчёты/тикеты/бэкапы разведены по разным топикам чата',
    '<b>TLS-алерты</b> — Telegram-уведомление при обновлении сертификата на любом из 5 серверов',
    '<b>Автобэкап + ротация логов</b> — ежедневно, с отправкой архива в чат',
]
story.append(ListFlowable(
    [ListItem(Paragraph(f, styles['Bullet']), leftIndent=10) for f in features],
    bulletType='bullet', start='•', bulletFontSize=8, leftIndent=6,
))

story.append(Paragraph('Куда идут уведомления', styles['H2']))
topics_data = [
    ['Топик', 'Что туда падает'],
    ['2', 'Покупки, продления, триалы, баланс, промо, партнёры'],
    ['441', 'Ноды, CRM-биллинг, сервис, ошибки'],
    ['6', 'Трафик ноды, ежедневные/недельные отчёты о продажах'],
    ['11', 'Тикеты поддержки (в т.ч. заявки на оплату)'],
    ['13', 'Бэкапы, ротация логов, TLS-сертификаты'],
]
t = Table(topics_data, colWidths=[18 * mm, 140 * mm])
t.setStyle(TableStyle([
    ('FONTNAME', (0, 0), (-1, 0), 'BodyBold'),
    ('FONTNAME', (0, 1), (-1, -1), 'Body'),
    ('FONTSIZE', (0, 0), (-1, -1), 9),
    ('BACKGROUND', (0, 0), (-1, 0), BLUE),
    ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
    ('ROWBACKGROUNDS', (0, 1), (-1, -1), [colors.white, LIGHT_BG]),
    ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#D8E2EF')),
    ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
    ('TOPPADDING', (0, 0), (-1, -1), 5),
    ('BOTTOMPADDING', (0, 0), (-1, -1), 5),
    ('LEFTPADDING', (0, 0), (-1, -1), 8),
]))
story.append(t)

story.append(Paragraph('Как обновить бота', styles['H2']))
story.append(Paragraph(
    '<b>Стабильный деплой</b> (зафиксированная проверенная версия, с автооткатом при сбое):', styles['Body']
))
story.append(Paragraph('cd /opt/bedolaga &amp;&amp; bash deploy_stable.sh', styles['Code']))
story.append(Spacer(1, 4))
story.append(Paragraph(
    '<b>Безопасное обновление</b> (подтягивает изменения автора бота, при конфликте — не ломает прод):',
    styles['Body']
))
story.append(Paragraph('cd /opt/bedolaga &amp;&amp; bash update_safe.sh', styles['Code']))
story.append(Spacer(1, 4))
story.append(Paragraph(
    '<b>Важно:</b> после правки <font face="BodyBold">.env</font> — всегда '
    '<font face="BodyBold">docker compose up -d bot</font>, не <font face="BodyBold">restart</font> '
    '(restart не перечитывает .env).',
    styles['BodySmall']
))

story.append(Paragraph('Установка с нуля', styles['H2']))
story.append(Paragraph(
    'bash &lt;(curl -4 -Ls "https://raw.githubusercontent.com/FnoUp/bedolaga_installer/main/install_bedolaga.sh")',
    styles['Code']
))
story.append(Paragraph(
    'Ставит бота на сервер с уже работающей Remnawave Panel: конфиг, вебхуки, TLS-уведомления — автоматически. '
    'Тарифы/промогруппы/FAQ создаются потом через бота вручную (это бизнес-данные).',
    styles['BodySmall']
))

story.append(Paragraph('Что можно улучшить дальше', styles['H2']))
ideas = [
    'Подключить платёжный шлюз (YooKassa/CryptoBot) — сейчас только Stars и вручную «через поддержку»',
    'Заполнить FAQ и промокоды — сейчас пусто',
    'Фаервол + мониторинг (Grafana) на серверах',
    'Автобэкап с периодической проверкой восстановления',
]
story.append(ListFlowable(
    [ListItem(Paragraph(f, styles['Bullet']), leftIndent=10) for f in ideas],
    bulletType='bullet', start='•', bulletFontSize=8, leftIndent=6,
))

story.append(Spacer(1, 10))
story.append(HRFlowable(width='100%', thickness=0.5, color=colors.HexColor('#D8E2EF')))
story.append(Paragraph(
    'Полный технический лог всех изменений — LOG_support_payment_2026-07-01.md в репозитории bedolaga_installer.',
    styles['BodySmall']
))

doc.build(story)
print('PDF готов')
