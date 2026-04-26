---
name: audit-installation
description: Аудит пользовательской инсталляции IWE. Запускает scripts/iwe-audit.sh + MCP healthcheck, передаёт отчёт subagent'у в роли VR.R.002 Аудитор (context isolation) → verdict ✅/⚠️/❌ по 4 компонентам (L1, ритуалы, MCP, DS-strategy). Используй после restore из бэкапа, после update.sh, или при еженедельной сверке.
argument-hint: "[--skip-mcp] [--critical]"
---

# Аудит инсталляции IWE

> **Service Clause:** [VR.SC.005-installation-audit](https://github.com/{{GITHUB_USER}}/PACK-verification/blob/main/pack/verification/08-service-clauses/VR.SC.005-installation-audit.md)
> **Роль:** VR.R.002 Аудитор (PACK-verification) — субагент с context isolation
> **Принцип:** детектор отчитывается, оператор делает (см. `scripts/iwe-drift.sh:7-11`). Auto-fix не входит в обещание.

Аргументы: $ARGUMENTS

## Обещание

За ≤5 минут — markdown-отчёт ✅/⚠️/❌ по 4 компонентам инсталляции:
1. **L1 (платформа)** — drift с FMT-exocortex-template
2. **Ритуалы** — smoke-test `/day-open`, `/day-close` (deferred до dry-run mode — пока inventory check)
3. **MCP** — healthcheck 4 tools
4. **DS-strategy** — git status + diff с FMT-strategy-template

Verdict выносит subagent в роли Аудитора, читая отчёт **без знаний о текущей сессии** (context isolation).

## Шаг 1. Детерминированные проверки (bash)

Запустить `bash $HOME/IWE/scripts/iwe-audit.sh` (передать `--critical` если в $ARGUMENTS), сохранить вывод в переменную `bash_report`. Проверить exit code:
- 0 → bash-часть ✅
- 1 → warnings (отметить, продолжать)
- 2 → critical gaps в bash-проверках (отметить, продолжать — Аудитор оценит совокупно с MCP)

Скрипт покрывает разделы 1-3 отчёта (Inventory, L1 drift, DS-strategy).

## Шаг 2. MCP healthcheck (если не `--skip-mcp`)

Параллельно вызвать 4 MCP tool'а с минимальной нагрузкой, замерить латентность:

| Tool | Параметры | Уровень | Что считаем |
|------|-----------|---------|-------------|
| `mcp__claude_ai_IWE__knowledge_search` | `query: "test"`, `limit: 1` | бесплатный | ✅ если ответ <15s |
| `mcp__claude_ai_IWE__github_status` | (без параметров) | бесплатный | ✅ если ответ |
| `mcp__claude_ai_IWE__personal_search` | `query: "ping"`, `limit: 1` | **подписочный** | ✅ если ответ; **403/subscription_required → ⏸️** (не считать failure) |
| `mcp__claude_ai_IWE__dt_read_digital_twin` | `path: "1_declarative"` | **подписочный** | ✅ если ответ; **403/subscription_required → ⏸️** (не считать failure) |

**Подписочное гейтование (DP.SC.112).** `personal_*` и `dt_*` требуют активной БР в `subscription_grants`. Без подписки — это **не сбой инсталляции**, а ожидаемый отказ. Помечать как ⏸️ subscription_required, не ❌. Coverage считать только по доступным для пользователя tool'ам.

Сформировать markdown-секцию `## 4. MCP healthcheck`:

```markdown
## 4. MCP healthcheck

| Tool | Статус | Латентность | Примечание |
|------|--------|-------------|------------|
| personal_search | ✅/❌ | Nms | ... |
| knowledge_search | ✅/❌ | Nms | ... |
| github_status | ✅/❌ | Nms | ... |
| dt_read_digital_twin | ✅/❌ | Nms | ... |

Coverage: N/4
```

Если `--skip-mcp` → секция «⏸️ MCP healthcheck — пропущен по флагу».

## Шаг 3. Сборка единого отчёта

```markdown
# IWE Installation Audit — YYYY-MM-DD HH:MM

[bash_report — секции 1-3]

[mcp_section — секция 4]

---
[передаётся Аудитору на шаг 4]
```

## Шаг 4. Запустить subagent в роли Аудитора (VR.R.002)

Использовать Agent tool с **context isolation** (subagent_type=general-purpose, модель Sonnet):

**⛔ Subagent НЕ получает:**
- Историю текущей сессии
- Знания о том, что пользователь чинил/восстанавливал
- Промежуточные рассуждения

**Subagent получает (промпт):**

```
Ты исполняешь роль VR.R.002 Аудитор (PACK-verification). Твоя задача — прочитать markdown-отчёт по аудиту инсталляции IWE и вынести verdict.

Эталон:
- VR.SC.005 (Service Clause): инсталляция должна иметь все критические L1-файлы, ритуалы должны загружаться, MCP должен отвечать, DS-strategy — быть git-репо.
- Gate-критерии (из WP-265 §Gate-критерии):
  - ✅ — 0 critical gaps, ≤2 warnings
  - ⚠️ — 1+ warning или ≥3 minor gaps; работоспособно
  - ❌ — ≥1 critical: L1 broken (>5 файлов drift), ритуал падает, MCP <2/4 отвечают

Принцип context isolation (VR.SOTA.002): не используй знания о том, как создавалась инсталляция. Оценивай ТОЛЬКО по отчёту.

Отчёт:
[вставить полный собранный отчёт]

Выдай verdict в формате:

## Verdict: [✅ / ⚠️ / ❌]

**Сводка по компонентам:**
- L1 (платформа): ✅/⚠️/❌ — короткое объяснение
- Ритуалы: ✅/⚠️/❌ — ...
- MCP: ✅/⚠️/❌ — ...
- DS-strategy: ✅/⚠️/❌ — ...

**Критичные gaps (если есть):**
- [список с указанием файла/компонента]

**Рекомендации:**
- Что чинить через `update.sh` (Синхронизатор)
- Что чинить руками (с конкретным шагом)
- Что отложить (некритично)

Не предлагай auto-fix. Не лезь в реализацию. Твоя роль — Аудитор, не Кодировщик.
```

## Шаг 5. Показать пользователю

Вывести:
1. Полный markdown-отчёт (секции 1-4)
2. Verdict от Аудитора
3. Краткое резюме одной строкой: `Verdict: ⚠️ Работоспособно с N оговорками. Подробнее выше.`

Пользователь сам решает, что чинить.

## Ограничения текущей реализации

- **Smoke-test ритуалов в реальном dry-run** — отложен. Сейчас inventory check (наличие SKILL.md). Реальный запуск `/day-open --dry-run` потребует флага в самих скиллах — отдельный РП.
- **DS-strategy diff** — работает только если существует `FMT-strategy-template`. Если нет — секция пометится «N/A».
- **MCP healthcheck** — зависит от текущих доступных tools. Если набор изменится, обновить шаг 2.
