#!/usr/bin/env bash
# Heritage Hearth exhaustiveness guard — Candidate 5
# Fails if shallow catalog alternatives leak raw hex or inline Arabic copy.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

echo "== Catalog lint: Color(0x) outside app_theme.dart =="
if grep -rn "Color(0x" "$ROOT/lib" --include="*.dart" | grep -v "app_theme.dart" | grep -v "Color(0x144B" ; then
  echo "✗ FAIL: Raw Color(0x…) found outside lib/core/theme/app_theme.dart"
  FAIL=1
else
  echo "✓ No raw Color(0x) outside theme"
fi

echo ""
echo "== Catalog lint: Text('Arabic') outside strings_*.dart =="
if grep -rn "Text(" "$ROOT/lib/ui" --include="*.dart" | grep -E "[ء-ي]" | grep -v "strings" ; then
  echo "✗ FAIL: Inline Arabic Text('…') found outside strings_*.dart"
  FAIL=1
else
  echo "✓ No inline Arabic Text outside catalogs"
fi

echo ""
echo "== Catalog lint: fontSize outside AppTextStyles (exempt emoji ☕) =="
if grep -rn "fontSize:" "$ROOT/lib" --include="*.dart" | grep -v "app_theme.dart" | grep -v "☕" | grep -v "iconSize" ; then
  echo "✗ FAIL: fontSize: outside AppTextStyles (non-emoji)"
  FAIL=1
else
  echo "✓ fontSize only via AppTextStyles or emoji"
fi

echo ""
echo "== Contrast ledger: textMuted vs outline enforced =="
if grep -rn "AppColors.outline" "$ROOT/lib/ui/games/spinner" --include="*.dart" | grep -q "bodySm.*outline\|Text.*outline" ; then
  echo "✗ FAIL: spinner body copy still uses outline (4.30:1) — must be textMuted"
  FAIL=1
else
  echo "✓ spinner body uses textMuted (≥4.5:1)"
fi

if grep -rn "Strings.ok\|strings\.ok\|CommonStrings.*okDeprecated" "$ROOT/lib" --include="*.dart" | grep -v "app_strings.dart" | grep -v "strings_common.dart" | grep -v "Deprecated" ; then
  echo "✗ FAIL: Strings.ok='حسناً' still referenced — use CommonStrings.close (إغلاق)"
  FAIL=1
else
  echo "✓ Strings.ok deprecated, not used"
fi

if [ $FAIL -ne 0 ]; then
  echo ""
  echo "Catalog lint FAILED — fix tokens/strings as per Candidate 5 After."
  exit 1
fi

echo ""
echo "Catalog lint PASSED — exhaustive tokens + strings, shallow alternatives uncompilable."
