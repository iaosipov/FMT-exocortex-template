Выполни сценарий Week Review для агента Стратег.

> **Триггер:** Автоматический — Пн 00:00 (полночь Вс→Пн, launchd).
> Создаёт WeekReport для клуба. Служит входом для session-prep (Пн 4:00).

Источник сценария: {{WORKSPACE_DIR}}/PACK-digital-platform/pack/digital-platform/02-domain-entities/DP.AGENT.012-strategist/scenarios/scheduled/03-week-review.md

## Контекст

- **WeekPlan:** {{WORKSPACE_DIR}}/DS-strategy/current/WeekPlan W*.md
- **Шаблон:** {{WORKSPACE_DIR}}/PACK-digital-platform/pack/digital-platform/02-domain-entities/DP.AGENT.012-strategist/templates/reviews/weekly-review.md

## Алгоритм

### 0. WakaTime — статистика рабочего времени

> Данные автоматически подставляются из WakaTime API (см. `{{WAKATIME_WEEK}}`).
> Включи секцию WakaTime в WeekReport после метрик и в пост для клуба.
> Сравни текущую и предыдущую неделю — укажи тренд (рост/спад/стабильно).
> Если данных нет — напиши: «WakaTime: нет данных (трекинг активен с 23 фев 2026)».

{{WAKATIME_WEEK}}

### 1. Сбор данных (Стратег собирает сам)

```bash
# Для КАЖДОГО репо в {{WORKSPACE_DIR}}/:
git -C {{WORKSPACE_DIR}}/<repo> log --since="last monday 00:00" --until="today 00:00" --oneline --no-merges
```

- Пройди по ВСЕМ репозиториям в `{{WORKSPACE_DIR}}/`
- Загрузи текущий WeekPlan из `DS-strategy/current/`
- Сопоставь коммиты с РП из WeekPlan
- Определи статус каждого РП: done / partial / not started

### 2. Статистика

- Completion rate: X/Y РП (N%)
- Коммитов всего
- Активных дней (дни с коммитами)
- По репозиториям (таблица)
- По системам (Созидатель, Экосистема, ИТ-платформа, Бот)

### 3. Инсайты

- Что получилось хорошо
- Что можно улучшить
- Блокеры (если были)
- Carry-over на следующую неделю

### 4. Формат для клуба

- Используй шаблон `weekly-review.md` (если есть)
- Добавь хештеги
- Формат: компактный, читаемый, с метриками

### 5. Сохранение

1. Создай `current/WeekReport W{N} YYYY-MM-DD.md`
2. Закоммить в DS-strategy

### 6. Создать пост для клуба (авто-публикация)

> Пост итогов недели публикуется автоматически в Пн 06:00 МСК. Стратег создаёт его сразу со `status: ready`.

1. На основе WeekReport сформируй пост для клуба:
   - Формат: по правилам `{{WORKSPACE_DIR}}/DS-Knowledge-Index-Tseren/CLAUDE.md` § 3 (аудитория `community`)
   - Структура: компактный отчёт (метрики, ключевые результаты, инсайты, что дальше)
   - Название: стандарт отчётов — `{Главное достижение}: W{N}, DD мес YYYY`
   - Выбери лучшее название сам (в автоматическом режиме нет пользователя для выбора)
   - Финал поста — сдержанный (см. CLAUDE.md § 3, правило сдержанности)

2. Создай файл `{{WORKSPACE_DIR}}/DS-Knowledge-Index-Tseren/docs/{YYYY}/{YYYY-MM-DD}-week-review-w{N}.md`

3. Frontmatter:

```yaml
---
type: post
title: "..."
audience: community
status: ready
created: YYYY-MM-DD
target: club
source_knowledge: null
tags: [итоги-недели, W{N}]
content_plan: null
---
```

4. Обнови `{{WORKSPACE_DIR}}/DS-Knowledge-Index-Tseren/docs/README.md` — добавь строку в начало текущего месяца
5. Закоммить и запушь `DS-Knowledge-Index-Tseren` (git add docs/ && git commit && git push)

**Шаблон WeekReport:**

```markdown
---
type: week-report
week: W{N}
date: YYYY-MM-DD
status: final
agent: Стратег
---

# WeekReport W{N}: DD мес — DD мес YYYY

## Метрики
- **РП:** X/Y завершено (N%)
- **Коммитов:** N в M репо
- **Активных дней:** N/7
- **WakaTime:** [общее время за неделю] (vs предыдущая: [время])

## По репозиториям

| Репо | Коммиты | Основные изменения |
|------|---------|-------------------|
| ... | ... | ... |

## РП

| # | РП | Статус | Комментарий |
|---|-----|--------|-------------|
| ... | ... | done/partial/⬜ | ... |

## Инсайты
- ...

## Carry-over
- ...

---

*Создан: YYYY-MM-DD (Week Review)*
```

Результат:
- WeekReport в `current/` — как вход для session-prep
- Пост итогов в `DS-Knowledge-Index-Tseren/docs/{YYYY}/` со `status: ready` — авто-публикация Пн 06:00
