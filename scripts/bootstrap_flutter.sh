#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../apps/mobile_flutter"
flutter create . \
  --project-name ahla_shabab_management_os \
  --org org.ahlashabab \
  --platforms android,ios
python ../../scripts/configure_flutter_platforms.py
flutter pub get
flutter analyze
flutter test
