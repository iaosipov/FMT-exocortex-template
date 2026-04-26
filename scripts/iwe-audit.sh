#!/usr/bin/env bash
# iwe-audit.sh — оркестратор аудита инсталляции IWE
#
# WP-265 Ф2, 2026-04-26.
# Service Clause: PACK-verification/.../08-service-clauses/VR.SC.005-installation-audit.md
#
# РОЛЬ: R8 Синхронизатор — собирает 3 детерминированных раздела
# (Inventory, L1 drift, DS-strategy) и формирует markdown-отчёт.
# Раздел 4 (MCP healthcheck) и verdict в роли VR.R.002 Аудитор —
# зона скилла-обёртки `/audit-installation`, не этого скрипта.
#
# Принцип «детектор отчитывается, оператор делает» (см. iwe-drift.sh:7-11):
# скрипт ТОЛЬКО детектит и пишет markdown. Никаких автофиксов.
#
# Usage:
#   bash iwe-audit.sh                  # полный отчёт
#   bash iwe-audit.sh --critical       # передать --critical в iwe-drift.sh
#   bash iwe-audit.sh --root PATH      # указать $IWE_ROOT (default: $HOME/IWE)
#   bash iwe-audit.sh -h | --help
#
# Exit code:
#   0 — всё ОК
#   1 — warnings (отсутствует ≤2 опциональных файла)
#   2 — критичные gaps (≥1 обязательного файла нет)
#
# Требования: bash, git, stat, awk (POSIX). Без внешних зависимостей.
# macOS-совместимо (stat -f vs stat -c — детектится в runtime).

set -eu

IWE_ROOT="${IWE_ROOT:-$HOME/IWE}"
DRIFT_CRITICAL=""

while [ $# -gt 0 ]; do
    case "$1" in
        --critical) DRIFT_CRITICAL="--critical"; shift ;;
        --root) IWE_ROOT="$2"; shift 2 ;;
        -h|--help)
            grep '^#' "$0" | head -28
            exit 0
            ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$IWE_ROOT" ]; then
    echo "IWE_ROOT not found: $IWE_ROOT" >&2
    exit 2
fi

# ---------- Helpers ----------

# Проверка существования файла/директории/симлинка с разрешением симлинков.
# Возвращает 0 если есть (любой тип), 1 иначе.
exists_any() {
    local p="$1"
    [ -e "$p" ] || [ -L "$p" ]
}

# Печать строки таблицы для inventory.
# Аргументы: путь (относительно IWE_ROOT), required (1/0), note
emit_inventory_row() {
    local rel="$1"
    local required="$2"
    local note="${3:-}"
    local abs="$IWE_ROOT/$rel"
    local status

    if exists_any "$abs"; then
        status="✅"
        if [ -L "$abs" ] && [ -z "$note" ]; then
            note="symlink"
        fi
        FOUND=$((FOUND + 1))
    else
        if [ "$required" = "1" ]; then
            status="❌"
            CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
        else
            status="⚠️"
            OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
        fi
    fi
    TOTAL=$((TOTAL + 1))
    printf "| \`%s\` | %s | %s |\n" "$rel" "$status" "$note"
}

# ---------- Заголовок ----------

NOW=$(date '+%Y-%m-%d %H:%M')
echo "# IWE Installation Audit — $NOW"
echo ""
echo "_Root:_ \`$IWE_ROOT\`"
echo ""

# ---------- Раздел 1: Inventory ----------

echo "## 1. Inventory (структура файлов)"
echo ""
echo "| Файл | Статус | Примечание |"
echo "|---|---|---|"

TOTAL=0
FOUND=0
CRITICAL_MISSING=0
OPTIONAL_MISSING=0

# CLAUDE.md — обязателен
emit_inventory_row "CLAUDE.md" 1 ""

# MEMORY.md — обязателен; может быть симлинком на auto-memory
# В этой инсталляции MEMORY.md живёт в memory/ — проверяем оба варианта
if exists_any "$IWE_ROOT/MEMORY.md"; then
    emit_inventory_row "MEMORY.md" 1 ""
elif exists_any "$IWE_ROOT/memory/MEMORY.md"; then
    # MEMORY.md в memory/ — это auto-memory layout
    TOTAL=$((TOTAL + 1))
    FOUND=$((FOUND + 1))
    printf "| \`%s\` | %s | %s |\n" "MEMORY.md" "✅" "в memory/MEMORY.md (auto-memory layout)"
else
    TOTAL=$((TOTAL + 1))
    CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
    printf "| \`%s\` | %s | %s |\n" "MEMORY.md" "❌" "не найден ни в корне, ни в memory/"
fi

# .claude/sync-manifest.yaml — обязателен (источник для iwe-drift)
emit_inventory_row ".claude/sync-manifest.yaml" 1 ""

# Правила
emit_inventory_row ".claude/rules/distinctions.md" 1 ""
emit_inventory_row ".claude/rules/formatting.md" 1 ""

# Скиллы (минимум day-open / day-close)
emit_inventory_row ".claude/skills/day-open/SKILL.md" 1 ""
emit_inventory_row ".claude/skills/day-close/SKILL.md" 1 ""

# Протоколы
emit_inventory_row "memory/protocol-open.md" 1 ""
emit_inventory_row "memory/protocol-work.md" 1 ""
emit_inventory_row "memory/protocol-close.md" 1 ""

# Скрипты
# update.sh: на user-инсталляции живёт в scripts/. На автор-инсталляции
# (params.yaml: author_mode: true) — в FMT-exocortex-template/. Адаптивно.
AUTHOR_MODE=0
if [ -f "$IWE_ROOT/params.yaml" ] && grep -qE "^author_mode:[[:space:]]*true" "$IWE_ROOT/params.yaml"; then
    AUTHOR_MODE=1
fi
if [ "$AUTHOR_MODE" = "1" ]; then
    if exists_any "$IWE_ROOT/FMT-exocortex-template/update.sh"; then
        TOTAL=$((TOTAL + 1)); FOUND=$((FOUND + 1))
        printf "| \`%s\` | %s | %s |\n" "scripts/update.sh" "✅" "author_mode: source в FMT-exocortex-template/update.sh"
    else
        TOTAL=$((TOTAL + 1)); CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
        printf "| \`%s\` | %s | %s |\n" "scripts/update.sh" "❌" "author_mode: не найден ни в scripts/, ни в FMT-exocortex-template/"
    fi
else
    emit_inventory_row "scripts/update.sh" 1 ""
fi
emit_inventory_row "scripts/iwe-drift.sh" 1 ""

# params.yaml — конфиг
emit_inventory_row "params.yaml" 1 ""

# DS-strategy — директория с .git
DS_DIR="$IWE_ROOT/DS-strategy"
TOTAL=$((TOTAL + 1))
if [ -d "$DS_DIR" ]; then
    if [ -d "$DS_DIR/.git" ]; then
        FOUND=$((FOUND + 1))
        printf "| \`%s\` | %s | %s |\n" "DS-strategy/" "✅" "git-репо (is_git=true)"
    else
        OPTIONAL_MISSING=$((OPTIONAL_MISSING + 1))
        printf "| \`%s\` | %s | %s |\n" "DS-strategy/" "⚠️" "директория есть, но не git-репо"
    fi
else
    CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
    printf "| \`%s\` | %s | %s |\n" "DS-strategy/" "❌" "директория не найдена"
fi

echo ""
echo "**coverage:** $FOUND/$TOTAL (отсутствует: критичных=$CRITICAL_MISSING, опциональных=$OPTIONAL_MISSING)"
echo ""

# ---------- Раздел 2: L1 drift ----------

echo "## 2. L1 drift (платформа vs FMT)"
echo ""

DRIFT_SCRIPT="$IWE_ROOT/scripts/iwe-drift.sh"
if [ -f "$DRIFT_SCRIPT" ]; then
    # Не валим весь скрипт если iwe-drift падает — set -eu выключаем точечно
    set +e
    if [ -n "$DRIFT_CRITICAL" ]; then
        bash "$DRIFT_SCRIPT" --critical
        DRIFT_RC=$?
    else
        bash "$DRIFT_SCRIPT"
        DRIFT_RC=$?
    fi
    set -e
    if [ $DRIFT_RC -ne 0 ]; then
        echo ""
        echo "_iwe-drift.sh exit code: $DRIFT_RC_"
    fi
else
    echo "❌ \`scripts/iwe-drift.sh\` не найден — drift-сверка пропущена"
fi
echo ""

# ---------- Раздел 3: DS-strategy ----------

echo "## 3. DS-strategy"
echo ""

if [ ! -d "$DS_DIR/.git" ]; then
    echo "❌ \`DS-strategy\` не git-репо (или директория отсутствует)"
else
    set +e
    DS_STATUS=$(git -C "$DS_DIR" status --short 2>&1)
    DS_STATUS_RC=$?
    set -e

    if [ $DS_STATUS_RC -ne 0 ]; then
        echo "⚠️ \`git status\` упал (rc=$DS_STATUS_RC):"
        echo ""
        echo '```'
        echo "$DS_STATUS"
        echo '```'
    else
        if [ -z "$DS_STATUS" ]; then
            DS_CHANGES_COUNT=0
        else
            DS_CHANGES_COUNT=$(printf '%s\n' "$DS_STATUS" | wc -l | tr -d ' ')
        fi
        echo "**Uncommitted changes:** $DS_CHANGES_COUNT"
        if [ "$DS_CHANGES_COUNT" -gt 0 ]; then
            echo ""
            echo '```'
            # Показываем не больше 30 строк, чтобы не раздувать отчёт
            printf '%s\n' "$DS_STATUS" | head -30
            if [ "$DS_CHANGES_COUNT" -gt 30 ]; then
                echo "... (ещё $((DS_CHANGES_COUNT - 30)) строк)"
            fi
            echo '```'
        fi
    fi

    echo ""
    echo "### Diff с FMT-strategy-template"
    echo ""

    FMT_DIR="$IWE_ROOT/FMT-strategy-template"
    if [ ! -d "$FMT_DIR" ]; then
        echo "_N/A — \`FMT-strategy-template\` не найден (это нормально, шаблон может ещё не существовать)._"
    else
        set +e
        FMT_DIFF=$(diff -rq "$DS_DIR/" "$FMT_DIR/" 2>&1)
        FMT_DIFF_RC=$?
        set -e

        if [ -z "$FMT_DIFF" ]; then
            echo "_Нет файловых различий._"
        else
            FMT_DIFF_COUNT=$(printf '%s\n' "$FMT_DIFF" | wc -l | tr -d ' ')
            echo "**Различий (файловый уровень):** $FMT_DIFF_COUNT (показаны топ-30)"
            echo ""
            echo '```'
            printf '%s\n' "$FMT_DIFF" | head -30
            if [ "$FMT_DIFF_COUNT" -gt 30 ]; then
                echo "... (ещё $((FMT_DIFF_COUNT - 30)) строк)"
            fi
            echo '```'
        fi
    fi
fi

echo ""

# ---------- Exit code ----------

# 2 = критичные gaps; 1 = warnings; 0 = ОК
if [ $CRITICAL_MISSING -ge 1 ]; then
    exit 2
fi
if [ $OPTIONAL_MISSING -gt 0 ]; then
    exit 1
fi
exit 0
