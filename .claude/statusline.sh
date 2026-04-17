#!/usr/bin/env bash
input=$(cat)
echo "$input" > /tmp/statusline_debug.json

PYTHON=""
if command -v python3 &>/dev/null && python3 -c "" 2>/dev/null; then
  PYTHON="python3"
elif command -v python &>/dev/null && python -c "" 2>/dev/null; then
  PYTHON="python"
fi

if [ -z "$PYTHON" ]; then
  echo "no python"
  exit 0
fi

echo "$input" | $PYTHON -c "
import sys, json
sys.stdout.reconfigure(encoding='utf-8')

RESET  = '\033[0m'
GRAY   = '\033[90m'
GREEN  = '\033[32m'
YELLOW = '\033[33m'
RED    = '\033[91m'
WHITE  = '\033[97m'

def color(pct):
    if pct == '?' or pct is None:
        return GRAY
    p = int(pct)
    if p >= 80: return RED
    if p >= 50: return YELLOW
    return GREEN

def bar(pct):
    if pct == '?' or pct is None:
        return '-----'
    filled = round(int(pct) / 100 * 5)
    return '#' * filled + '-' * (5 - filled)

from datetime import datetime, timezone

data = json.load(sys.stdin)
rl        = data.get('rate_limits', {})
five_hour = rl.get('five_hour', {}).get('used_percentage', '?')
seven_day = rl.get('seven_day', {}).get('used_percentage', '?')
fh_reset  = rl.get('five_hour', {}).get('resets_at')
sd_reset  = rl.get('seven_day', {}).get('resets_at')

def reset_time(ts):
    if not ts:
        return ''
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime('%H:%M')

def reset_date(ts):
    if not ts:
        return ''
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().strftime('%m/%d')

def block(title, pct, reset_label, reset_str):
    c = color(pct)
    reset_part = f'{GRAY} {reset_label} {reset_str}{RESET}' if reset_str else ''
    return (
        f'{GRAY}[{RESET} '
        f'{WHITE}{title}{RESET} '
        f'{c}{bar(pct)} {pct}%{RESET}'
        f'{reset_part}'
        f' {GRAY}]{RESET}'
    )

parts = [
    block('5h Rate', five_hour, 'reset', reset_time(fh_reset)),
    block('7d Rate', seven_day, 'expire', reset_date(sd_reset)),
]
print('  '.join(parts))
"
