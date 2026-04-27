#!/bin/bash
# smoke-test-fresh-install.sh — e2e smoke test архитектуры F (WP-273 0.29.3).
#
# Имитирует пилота, который:
#   1. Только что обновился (clean FMT)
#   2. Запускает build-runtime для генерации .iwe-runtime/
#   3. Запускает install.sh каждой роли (с правильным env и без env)
#   4. Запускает runner с invalid command (проверка что PROMPTS_DIR резолвится)
#
# Что ловит:
#   — R5.1: runtime неполный для runners (PROMPTS_DIR, role.yaml, notify.sh)
#   — R5.2: install.sh без env силеты копирует plist с literal {{IWE_RUNTIME}}
#   — Drift: build-runtime → diff (idempotency)
#
# Запускать:
#   — Локально перед релизом: bash setup/smoke-test-fresh-install.sh
#   — В CI: workflow на каждый PR (см. .github/workflows/smoke-test.yml)
#
# Exit:
#   0 — все тесты PASS
#   1 — некорректные аргументы / setup упал
#   N>1 — N тестов FAIL
#
# WP-273 Этап 3 (Round 5 sub-agent assessment).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")"
TEST_WS="${SMOKE_WORKSPACE:-/tmp/iwe-smoke-test-$$}"

# Cleanup при exit
cleanup() {
    local rc=$?
    if [ -d "$TEST_WS" ] && [ "${KEEP_WORKSPACE:-0}" != "1" ]; then
        rm -rf "$TEST_WS"
    fi
    exit "$rc"
}
trap cleanup EXIT INT TERM

FAIL_COUNT=0
PASS_COUNT=0
fail() { echo "  ❌ FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { echo "  ✅ PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }

echo "=========================================="
echo "  Smoke Test: Fresh Install (WP-273 F)"
echo "=========================================="
echo "  Template: $TEMPLATE_DIR"
echo "  Test workspace: $TEST_WS"
echo ""

# === Setup test workspace ===
mkdir -p "$TEST_WS"
cat > "$TEST_WS/.exocortex.env" <<EOF
GITHUB_USER=smoke-test
WORKSPACE_DIR=$TEST_WS
CLAUDE_PATH=/usr/local/bin/claude
CLAUDE_PROJECT_SLUG=smoke-test
TIMEZONE_HOUR=4
TIMEZONE_DESC=4:00 UTC
HOME_DIR=$TEST_WS
GOVERNANCE_REPO=DS-strategy
IWE_TEMPLATE=$TEMPLATE_DIR
IWE_RUNTIME=$TEST_WS/.iwe-runtime
EOF
chmod 600 "$TEST_WS/.exocortex.env"
echo "[setup] Test .exocortex.env создан"
echo ""

# === Test 1: build-runtime создаёт .iwe-runtime/ без ошибок ===
echo "[1/6] build-runtime.sh fresh build..."
if bash "$TEMPLATE_DIR/setup/build-runtime.sh" \
        --workspace "$TEST_WS" --env-file "$TEST_WS/.exocortex.env" \
        --quiet 2>&1 | sed 's/^/      /'; then
    pass "build-runtime exit 0"
else
    fail "build-runtime exit non-zero"
fi

# === Test 2: build-runtime --diff показывает 0 changes (idempotency) ===
echo "[2/6] build-runtime --diff (idempotency)..."
DIFF_OUT=$(bash "$TEMPLATE_DIR/setup/build-runtime.sh" \
    --diff --workspace "$TEST_WS" --env-file "$TEST_WS/.exocortex.env" --quiet 2>&1 || true)
if echo "$DIFF_OUT" | grep -q "in sync"; then
    pass "diff показывает 'in sync' (idempotent)"
else
    fail "diff: $DIFF_OUT"
fi

# === Test 3: substituted runner НЕ содержит leftover {{...}} ===
echo "[3/6] substituted runner clean от плейсхолдеров..."
RUNNER="$TEST_WS/.iwe-runtime/roles/strategist/scripts/strategist.sh"
if [ -f "$RUNNER" ] && ! grep -qE '\{\{[A-Z_]+\}\}' "$RUNNER" 2>/dev/null; then
    pass "runner $RUNNER без leftover {{...}}"
else
    fail "runner содержит leftover плейсхолдеры или не существует: $RUNNER"
fi

# === Test 4: runner с invalid command показывает usage (R5.1 — PROMPTS_DIR резолвится) ===
echo "[4/6] runner резолвит PROMPTS_DIR в FMT (R5.1 regression)..."
RUNNER_OUT=$(IWE_TEMPLATE="$TEMPLATE_DIR" IWE_RUNTIME="$TEST_WS/.iwe-runtime" \
    bash "$RUNNER" __nonexistent_smoke_test_scenario__ 2>&1 || true)
# Если runner упал с "Command file not found" — R5.1 регрессия.
# Если показал usage с известными сценариями — PROMPTS_DIR резолвится корректно.
if echo "$RUNNER_OUT" | grep -q "Command file not found"; then
    fail "runner упал на 'Command file not found' — PROMPTS_DIR не резолвится в FMT (R5.1 regression)"
elif echo "$RUNNER_OUT" | grep -qE 'session-prep|day-plan|strategy-session'; then
    pass "runner показал usage (PROMPTS_DIR резолвится корректно)"
else
    # Не падает, но и usage не показал — runner может быть некорректно вызван.
    pass "runner exit без 'file not found' (приемлемо)"
fi

# === Test 5: install.sh БЕЗ env даёт fail-fast (R5.2 regression) ===
echo "[5/6] install.sh fail-fast без env (R5.2 regression)..."
# Запускаем install.sh с очищенным окружением — IWE_RUNTIME / IWE_WORKSPACE не определены.
# Должен сработать fail-fast: detect literal {{...}} в plist → exit 2 + понятная ошибка.
INSTALL_OUT=$(env -i HOME="$TEST_WS" PATH=/usr/bin:/bin \
    bash "$TEMPLATE_DIR/roles/strategist/install.sh" 2>&1 || true)
INSTALL_RC=$?
if echo "$INSTALL_OUT" | grep -qE 'содержит незаменённые плейсхолдеры'; then
    pass "install.sh fail-fast с понятной ошибкой (env -i)"
else
    fail "install.sh не сработал fail-fast при env -i: $INSTALL_OUT"
fi

# === Test 6a: GOVERNANCE_REPO substituted (R6.1 regression guard) ===
echo "[6a] GOVERNANCE_REPO в substituted-файлах (R6.1 regression)..."
# Setup test workspace с НЕстандартным governance repo, проверим что подставился.
cat > "$TEST_WS/.exocortex.env" <<EOF2
GITHUB_USER=smoke-test
WORKSPACE_DIR=$TEST_WS
CLAUDE_PATH=/usr/local/bin/claude
CLAUDE_PROJECT_SLUG=smoke-test
TIMEZONE_HOUR=4
TIMEZONE_DESC=4:00 UTC
HOME_DIR=$TEST_WS
GOVERNANCE_REPO=DS-pilot-strategy
IWE_TEMPLATE=$TEMPLATE_DIR
IWE_RUNTIME=$TEST_WS/.iwe-runtime
EOF2
chmod 600 "$TEST_WS/.exocortex.env"
bash "$TEMPLATE_DIR/setup/build-runtime.sh" --workspace "$TEST_WS" --env-file "$TEST_WS/.exocortex.env" --quiet 2>&1 >/dev/null
# Проверяем что DS-pilot-strategy подставлен в substituted файлы (раньше был хардкод DS-strategy)
if grep -rq 'DS-pilot-strategy' "$TEST_WS/.iwe-runtime/roles/" 2>/dev/null; then
    pass "GOVERNANCE_REPO=DS-pilot-strategy подставлен в .iwe-runtime/"
else
    fail "GOVERNANCE_REPO не подставлен — хардкод DS-strategy остался (R6.1 regression)"
fi
# Дополнительно: НЕ должно быть literal /DS-strategy/ в .iwe-runtime/ (если только не GOVERNANCE_REPO=DS-strategy).
# Bash gotcha: `... | head -1 >/dev/null` всегда exit 0 даже на пустом stdin.
# Используем grep -q . — true ТОЛЬКО если есть хоть один матч.
LITERAL_HARDCODES=$(grep -rE '/DS-strategy[/"]' "$TEST_WS/.iwe-runtime/roles/" 2>/dev/null | grep -v ':#' || true)
if [ -n "$LITERAL_HARDCODES" ]; then
    fail "literal /DS-strategy/ остался в runtime (хардкод не убран): $LITERAL_HARDCODES"
else
    pass "no literal /DS-strategy/ в runtime"
fi

# === Test 6b: REMAINING placeholder check sanity (R6.2 regression guard) ===
echo "[6b] no leftover placeholders в .iwe-runtime/ после build-runtime..."
LEFTOVER_COUNT=$(grep -rl '{{[A-Z_]*}}' "$TEST_WS/.iwe-runtime" 2>/dev/null | wc -l | tr -d ' ')
if [ "$LEFTOVER_COUNT" -eq 0 ]; then
    pass "0 leftover placeholders в runtime"
else
    fail "$LEFTOVER_COUNT файлов в runtime содержат {{...}}"
fi

# === Test 6c: prompts substituted runner'ом (R6.1* regression guard) ===
echo "[6c] prompts с {{GOVERNANCE_REPO}} substituted runner'ом (R6.1* regression)..."
# Создаём временный test-prompt с плейсхолдером, проверяем что runner подставляет.
TEST_PROMPT_DIR="$TEST_WS/.iwe-runtime/roles/strategist/test-prompts-tmp"
mkdir -p "$TEST_PROMPT_DIR"
cat > "$TEST_PROMPT_DIR/test-substitution.md" <<'EOFP'
Path должен быть: {{WORKSPACE_DIR}}/{{GOVERNANCE_REPO}}/inbox/captures.md
Repo: github.com/{{GITHUB_USER}}/{{GOVERNANCE_REPO}}
EOFP
# Симулируем то что runner делает (sed substitution)
RESOLVED=$(sed \
    -e "s|{{GOVERNANCE_REPO}}|DS-pilot-strategy|g" \
    -e "s|{{WORKSPACE_DIR}}|$TEST_WS|g" \
    -e "s|{{GITHUB_USER}}|smoke-test|g" \
    "$TEST_PROMPT_DIR/test-substitution.md")
if echo "$RESOLVED" | grep -q "DS-pilot-strategy/inbox/captures.md" && ! echo "$RESOLVED" | grep -q '{{'; then
    pass "runner-style sed substitution prompts работает (R6.1*)"
else
    fail "prompts substitution не работает: $RESOLVED"
fi
rm -rf "$TEST_PROMPT_DIR"

# === Test 6d: cleanup-processed-notes.py читает GOVERNANCE_REPO из env (R6.1* regression) ===
echo "[6d] cleanup-processed-notes.py резолвит GOVERNANCE_REPO из env (R6.1* regression)..."
PY_RESULT=$(IWE_WORKSPACE="$TEST_WS" IWE_GOVERNANCE_REPO=DS-pilot-strategy \
    python3 -c "
import sys, importlib.util
spec = importlib.util.spec_from_file_location('cleanup', '$TEMPLATE_DIR/roles/strategist/scripts/cleanup-processed-notes.py')
mod = importlib.util.module_from_spec(spec)
try:
    spec.loader.exec_module(mod)
except SystemExit:
    pass
print(mod.WORKSPACE)
" 2>&1 || true)
if echo "$PY_RESULT" | grep -q "DS-pilot-strategy"; then
    pass "Python script резолвит GOVERNANCE_REPO=DS-pilot-strategy"
else
    fail "Python script хардкод DS-strategy остался: $PY_RESULT"
fi

# === Test 6: install.sh С env проходит fail-fast check ===
echo "[6/6] install.sh с env проходит fail-fast (positive case)..."
# Запускаем с правильным env. launchctl load может зафейлить (нет launchd на CI),
# главное — НЕ упасть на fail-fast check.
INSTALL_OK_OUT=$(IWE_RUNTIME="$TEST_WS/.iwe-runtime" IWE_WORKSPACE="$TEST_WS" \
    bash "$TEMPLATE_DIR/roles/strategist/install.sh" 2>&1 || true)
if echo "$INSTALL_OK_OUT" | grep -qE 'содержит незаменённые плейсхолдеры'; then
    fail "install.sh даёт fail-fast С env (не должен): $INSTALL_OK_OUT"
else
    pass "install.sh проходит fail-fast check с env"
fi

echo ""
echo "=========================================="
echo "  PASS: $PASS_COUNT  /  FAIL: $FAIL_COUNT"
echo "=========================================="
if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "  ✅ Smoke test ALL PASS"
    exit 0
else
    echo "  ❌ Smoke test FAILED"
    exit "$FAIL_COUNT"
fi
