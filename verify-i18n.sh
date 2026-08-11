#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

echo "=== i18n verification ==="
echo ""

# 1. Metadata localized
echo "[1] Metadata localized fields"
if python3 -c "import json; d=json.load(open('metadata.json')); assert 'Name[es]' in d['KPlugin'] and 'Description[es]' in d['KPlugin']"; then
  echo "  ✅ Name[es] and Description[es] present"
  python3 -c "import json; d=json.load(open('metadata.json')); print(d['KPlugin']['Name[es]']); print(d['KPlugin']['Description[es]'])"
else
  echo "  ❌ Missing Name[es]/Description[es]"
fi
echo ""

# 2. .mo exists
MO="contents/locale/es/LC_MESSAGES/plasma_applet_org.kde.plasma.rclone-mounts.mo"
echo "[2] .mo file"
if [ -f "$MO" ]; then
  echo "  ✅ $MO exists ($(stat -c%s "$MO") bytes)"
else
  echo "  ❌ $MO missing"
fi
echo ""

# 3. .mo content sample
echo "[3] Sample translations from .mo"
if command -v msgunfmt >/dev/null 2>&1 && [ -f "$MO" ]; then
  msgunfmt "$MO" | grep -A1 'msgid "Mounts"' | head -n 4 || true
  msgunfmt "$MO" | grep -A1 'msgid "Rclone Mounts"' | head -n 4 || true
else
  echo "  msgunfmt not available"
fi
echo ""

# 4. QML i18n usage
echo "[4] QML i18n usage count"
COUNT=$(grep -r "i18n(" contents/ui | wc -l)
echo "  Found $COUNT occurrences of i18n( in QML"
echo ""

# 5. How to test with plasmoidviewer
echo "[5] Test commands"
echo "  Installed: LANGUAGE=\"es:es\" LANG=\"es_ES.UTF-8\" plasmoidviewer --applet org.kde.plasma.rclone-mounts"
echo "  From source: LANGUAGE=\"es:es\" LANG=\"es_ES.UTF-8\" plasmoidviewer --applet $ROOT"
echo ""

echo "=== Done ==="
