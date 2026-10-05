#!/usr/bin/env bash
# routing: skill  trigger=strategy-session  deterministic=true
# strategy-focus-hash.sh — машинная привязка сверки недели к версии месячной
# рамки (WP-518, шаг 06a strategy-session-weekly). Печатает sha256 активной
# фокус-секции — НЕ доказательство осмысления, только фиксация версии текста.
#
# Использование: strategy-focus-hash.sh <путь к Strategy.md|monthly-priorities.md>
# Выход: одна строка с hex-хешем (stdout). Диагностика — stderr.
# Exit: 0 — хеш посчитан; 1 — файл не найден/нечитаем; 2 — ошибка вызова.
#
# Контракт извлечения (документирован, не эвристика по содержимому):
#   - в файле есть маркер «Фокус:» (заголовок `### Фокус: <месяц>` или
#     `<summary><b>Фокус: ...</b></summary>` в details-блоке) — хешируется
#     ПОСЛЕДНЯЯ такая секция: от строки маркера до следующего заголовка
#     второго уровня `## ` (не включительно) или конца файла. Секции в
#     Strategy.md идут хронологически, последняя — активный месяц.
#   - маркера «Фокус:» нет (формат monthly-priorities.md) — хешируется часть
#     от начала файла до первого заголовка `## Архив` (не включительно);
#     без него — весь файл.
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  sed -n '2,20p' "$0"
  exit 0
fi
if [ "$#" -ne 1 ]; then
  echo "ERROR: ожидается ровно один аргумент — путь к файлу рамки месяца" >&2
  echo "Использование: strategy-focus-hash.sh <Strategy.md|monthly-priorities.md>" >&2
  exit 2
fi
FOCUS_FILE="$1"
if [ ! -r "$FOCUS_FILE" ]; then
  echo "ERROR: файл не найден или нечитаем: $FOCUS_FILE" >&2
  exit 1
fi

section=$(awk '
  /^## / && !/Фокус:/ { if (in_focus) exit; if (archive_mode) exit }
  /Фокус:/ { in_focus=1; buf=""; next_is_section=1 }
  in_focus { buf = buf $0 "\n" }
  /^## Архив/ && !in_focus { archive_mode=1; exit }
  { if (!in_focus) head = head $0 "\n" }
  END {
    if (in_focus) printf "%s", buf
    else printf "%s", head
  }
' "$FOCUS_FILE")

if [ -z "$section" ]; then
  echo "ERROR: не удалось извлечь фокус-секцию из $FOCUS_FILE" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  printf '%s' "$section" | sha256sum | awk '{print $1}'
elif command -v shasum >/dev/null 2>&1; then
  printf '%s' "$section" | shasum -a 256 | awk '{print $1}'
elif command -v openssl >/dev/null 2>&1; then
  printf '%s' "$section" | openssl dgst -sha256 | awk '{print $NF}'
else
  echo "ERROR: нет ни sha256sum, ни shasum, ни openssl" >&2
  exit 1
fi
