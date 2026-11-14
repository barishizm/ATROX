#!/usr/bin/env bash
# P102: fails when a tracked file contains something that looks like a real credential.
# Placeholders (example.com, "<...>", "your-", "xxx", "changeme") and test fixtures are ignored on purpose.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

patterns=(
  '-----BEGIN (RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----'
  'sk-[A-Za-z0-9]{32,}'
  'sb_secret_[A-Za-z0-9_-]{16,}'
  'AKIA[0-9A-Z]{16}'
  'ghp_[A-Za-z0-9]{36}'
  'gh[ousr]_[A-Za-z0-9]{36}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'AIza[0-9A-Za-z_-]{35}'
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
  '(service_role|SERVICE_ROLE_KEY|DEEPSEEK_API_KEY|OPENROUTER_API_KEY|APPLE_PRIVATE_KEY)["'\'' ]*[:=]["'\'' ]*[A-Za-z0-9._/+-]{24,}'
)
ignore='(example|placeholder|your[-_]|changeme|<[a-z_ -]+>|xxxx|dummy|fake|test[-_ ]?(key|token|secret))'

status=0
for pattern in "${patterns[@]}"; do
  hits=$(git grep -nIE -e "$pattern" -- . ':!*.lock' ':!tools/scan-secrets.sh' ':!docs/GUVENLIK.md' ':!*.test.ts' ':!*.test.sql' | grep -viE "$ignore" || true)
  if [ -n "$hits" ]; then
    echo "Possible secret ($pattern):" >&2
    echo "$hits" | sed 's/^\([^:]*:[0-9]*\):.*/\1: <redacted>/' >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "secret scan: clean"
exit $status
