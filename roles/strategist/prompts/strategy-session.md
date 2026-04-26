Запусти стратегическую сессию через skill-диспетчер.

## Действие

Загрузи `{{IWE_TEMPLATE}}/.claude/skills/strategy-session/SKILL.md` и выполни инструкции этого skill полностью. Skill сам определит режим (initial / weekly / weekly без draft) по skeleton-маркеру и наличию артефактов в `{{WORKSPACE_DIR}}/{{GOVERNANCE_REPO}}/`.

## Зачем диспетчер

Раньше `strategist.sh strategy-session` шёл напрямую в weekly flow (`prompts/strategy-session-weekly.md`), требуя черновик от session-prep. На fresh setup или при initial-сессии это не работает: черновика ещё нет. Skill `/strategy-session` решает обе задачи единообразно — поэтому headless entrypoint теперь идёт через тот же skill, что и интерактивный slash-вызов.

## Контекст

- **Headless mode:** strategist.sh запускает Claude Code без интерактивного пользователя. Skill в headless должен:
  - Если режим = initial — записать TODO-разметку в `{{WORKSPACE_DIR}}/{{GOVERNANCE_REPO}}/inbox/initial-session-pending.md` и завершиться (вмешательство пользователя нужно вживую).
  - Если режим = weekly — провести шаги skill §3 с прогрузкой `prompts/strategy-session-weekly.md`.
  - Если weekly без draft — записать предупреждение в лог и завершиться.

- **Interactive mode:** через `/strategy-session` skill идёт тем же путём, но шаг initial выполняется в диалоге.

## Результат

См. инструкцию skill (`{{IWE_TEMPLATE}}/.claude/skills/strategy-session/SKILL.md`).
