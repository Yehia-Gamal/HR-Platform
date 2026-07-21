#!/usr/bin/env bash
# تشغيل تطبيق Flutter متصلاً بمشروع Supabase (Staging).
# الاستخدام:  ./run_staging.sh            (الجهاز الافتراضي)
#            ./run_staging.sh -d chrome   (متصفح للمعاينة)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFINE_FILE="$SCRIPT_DIR/dart_define/staging.json"

if [[ ! -f "$DEFINE_FILE" ]]; then
  echo "لم يتم العثور على $DEFINE_FILE — انسخ dart_define/staging.example.json إلى staging.json واملأ القيم." >&2
  exit 1
fi

echo "تشغيل Flutter متصلاً بـ Supabase (staging)..."
exec flutter run --dart-define-from-file="$DEFINE_FILE" "$@"
