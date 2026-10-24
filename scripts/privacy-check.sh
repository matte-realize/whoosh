#!/usr/bin/env bash
# Enforces the rules in .kiro/steering/privacy.md and the layering table in the spec design.
# Usage: scripts/privacy-check.sh <file.swift> [more files...]
# With no arguments, checks every Swift file under Whoosh/.
# Exits 1 and prints violations if any rule is broken; exits 0 otherwise.
set -o pipefail  # no -u: macOS bash 3.2 errors on empty arrays
cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(find Whoosh -name '*.swift' 2>/dev/null)
fi

fail=0
report() { echo "[privacy-check] $1: $2"; fail=1; }

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  case "$f" in *.swift) ;; *) continue ;; esac
  # Tests may fake anything.
  case "$f" in *Tests/*) continue ;; esac

  # 1. Network access only inside Services/Sync (opt-in Supabase sync).
  case "$f" in
    */Services/Sync/*) ;;
    *)
      if grep -nE 'URLSession|URLRequest|import Supabase|WKWebView' "$f" >/dev/null; then
        report "$f" "network API outside Services/Sync (privacy: no network unless sync is on)"
      fi
      ;;
  esac

  # 2. No analytics / tracking SDKs anywhere.
  if grep -nEi 'import (Firebase|FirebaseAnalytics|Amplitude|Mixpanel|Segment|Sentry|AppsFlyer|Adjust|Crashlytics)' "$f" >/dev/null; then
    report "$f" "analytics/tracking SDK import"
  fi

  # 3. Secrets must never be in source.
  if grep -nE 'service_role|eyJ[A-Za-z0-9_-]{20,}' "$f" >/dev/null; then
    report "$f" "possible secret (service_role or JWT-looking string)"
  fi

  # 4. Honest copy: never claim prediction/prevention of collisions.
  if grep -nEi '(prevent|predict|avoid|guarantee)[a-z]* (a |all |any |every )?(collision|crash|accident)s?' "$f" >/dev/null; then
    report "$f" "copy claims collision prevention/prediction (use 'experimental' framing)"
  fi

  # 5. Layering: Models and Metrics import Foundation only.
  case "$f" in
    */Models/*|*/Metrics/*)
      if grep -nE '^import (SwiftUI|CoreLocation|SwiftData|MapKit|UIKit|AVFoundation)' "$f" >/dev/null; then
        report "$f" "Models/Metrics must import Foundation only"
      fi
      ;;
  esac

  # 6. Views never touch Core Location or SwiftData directly.
  case "$f" in
    */Features/*View.swift|*/Views/*)
      if grep -nE '^import (CoreLocation|SwiftData)|CLLocationManager' "$f" >/dev/null; then
        report "$f" "Views must not use CoreLocation/SwiftData directly"
      fi
      ;;
  esac

  # 7. Camera permission is not requested in the MVP.
  if grep -nE 'AVCaptureDevice\.requestAccess|AVCaptureSession' "$f" >/dev/null; then
    case "$f" in
      */Services/Detection/*) ;;
      *) report "$f" "camera access outside Services/Detection (MVP must not request camera)" ;;
    esac
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "[privacy-check] OK (${#files[@]} file(s))"
fi
exit "$fail"
