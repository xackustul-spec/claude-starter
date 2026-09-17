#!/usr/bin/env bash
# Назначение: запуск хуков claude-starter на Linux/macOS/Git Bash — находит python3 и передаёт
# ему команду и JSON события. Нет Python 3 — молча пропускает (exit 0), чтобы не мешать работе.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cmd="${1:-}"
[ -n "$cmd" ] || exit 0
py=""
for c in python3 python py; do
  if command -v "$c" >/dev/null 2>&1; then
    if [ "$c" = "py" ]; then
      v="$("$c" -3 -c 'import sys;print(sys.version_info[0])' 2>/dev/null)"; [ "$v" = "3" ] && py="$c -3" && break
    else
      v="$("$c" -c 'import sys;print(sys.version_info[0])' 2>/dev/null)"; [ "$v" = "3" ] && py="$c" && break
    fi
  fi
done
[ -n "$py" ] || exit 0
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
exec $py "$here/kit_hooks.py" "$@"
