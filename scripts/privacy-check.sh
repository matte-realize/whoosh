#!/usr/bin/env bash
# Enforces the rules in .kiro/steering/privacy.md and the layering table in the specs
# (ride-recording-mvp design + crash-response design "Privacy and network invariants").
# Usage: scripts/privacy-check.sh <file.swift> [more files...]
# With no arguments, checks every Swift file under Whoosh/.
# Exits 1 and prints violations if any rule is broken; exits 0 otherwise.
#
# MVP rules (unchanged): 1 network only in Services/Sync, 2 no analytics SDKs,
# 3 no secrets, 4 honest copy, 5 Models/Metrics import Foundation only,
# 6 Views never touch CoreLocation/SwiftData, 7 camera only in Services/Detection.
# Crash-response additions: network also allowed in Services/Notification; provider
# credentials flagged anywhere; tel:/telprompt: only in Features/Emergency; MessageUI
# only in Support/Representables; CoreMotion only in Services/Crash; Keychain SecItem
# only in Services/Contacts; AVAudioSession only in Services/Alerts; and copy that
# claims emergency services were notified or that help is on the way.
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

  # 1. Network access only inside Services/Sync (opt-in ride sync) or
  #    Services/Notification (opt-in crash alerts).
  case "$f" in
    */Services/Sync/*) ;;
    */Services/Notification/*) ;;
    *)
      if grep -nE 'URLSession|URLRequest|import Supabase|WKWebView' "$f" >/dev/null; then
        report "$f" "network API outside Services/Sync and Services/Notification (privacy: no network unless ride sync or crash alerts is enabled)"
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

  # 3b. SMS-provider credentials must never appear in the app or repo; they live only
  #     as Edge Function secrets (privacy.md, crash-alert-contract.md §3).
  if grep -nE '\b(AC|SK|AP|MG)[0-9a-fA-F]{32}\b' "$f" >/dev/null; then
    report "$f" "possible SMS-provider credential (account-SID / API-key-like string)"
  fi
  if grep -nEi '(twilio|messagebird|vonage|nexmo|plivo|sinch)[^a-z]*(auth[_ ]?token|api[_ ]?key|account[_ ]?sid|secret)' "$f" >/dev/null; then
    report "$f" "possible SMS-provider credential (provider name in a key/token context)"
  fi

  # 4. Honest copy: never claim prediction/prevention of collisions.
  if grep -nEi '(prevent|predict|avoid|guarantee)[a-z]* (a |all |any |every )?(collision|crash|accident)s?' "$f" >/dev/null; then
    report "$f" "copy claims collision prevention/prediction (use 'experimental' framing)"
  fi

  # 4b. Honest copy: never claim emergency services were notified or that help is coming.
  if grep -nEi 'emergency services? (have been|has been|were|was|will be|are|is) (notified|called|contacted|dispatched|alerted)' "$f" >/dev/null; then
    report "$f" "copy claims emergency services were notified (Whoosh never contacts emergency services; cannot guarantee detection or delivery)"
  fi
  if grep -nEi 'help is on (the|its) way' "$f" >/dev/null; then
    report "$f" "copy claims help is on the way (never promise response; cannot guarantee detection or delivery)"
  fi

  # 5. Layering: Models and Metrics import Foundation only.
  case "$f" in
    */Models/*|*/Metrics/*)
      if grep -nE '^import (SwiftUI|CoreLocation|SwiftData|MapKit|UIKit|AVFoundation|CoreMotion|MessageUI|ContactsUI)' "$f" >/dev/null; then
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

  # 8. Never auto-call: tel:/telprompt: only from the rider-tapped button in Features/Emergency.
  if grep -nE 'tel(prompt)?:' "$f" >/dev/null; then
    case "$f" in
      */Features/Emergency/*) ;;
      *) report "$f" "tel:/telprompt: outside Features/Emergency (Whoosh never auto-calls; 911 is a rider-tapped control only)" ;;
    esac
  fi

  # 9. The SMS composer is a rider-initiated fallback only; confine MessageUI to the
  #    UIKit wrapper so a service can never make it an automatic path.
  if grep -nE 'import MessageUI|MFMessageComposeViewController' "$f" >/dev/null; then
    case "$f" in
      */Support/Representables/*) ;;
      *) report "$f" "MessageUI/MFMessageComposeViewController outside Support/Representables (composer is a rider-initiated fallback only)" ;;
    esac
  fi

  # 10. Core Motion only in the crash detector folder (the only motion consumer).
  if grep -nE 'import CoreMotion|CMMotionManager|CMMotionActivityManager' "$f" >/dev/null; then
    case "$f" in
      */Services/Crash/*) ;;
      *) report "$f" "CoreMotion outside Services/Crash (only the crash detector may read motion)" ;;
    esac
  fi

  # 11. Keychain APIs only where emergency contacts are stored.
  if grep -nE 'SecItem(Add|Copy|Update|Delete)Matching?|SecItemAdd|SecItemCopyMatching|SecItemUpdate|SecItemDelete' "$f" >/dev/null; then
    case "$f" in
      */Services/Contacts/*) ;;
      *) report "$f" "Keychain SecItem APIs outside Services/Contacts (contacts are the only Keychain data)" ;;
    esac
  fi

  # 12. AVAudioSession only in Services/Alerts (the countdown feedback).
  if grep -nE 'AVAudioSession' "$f" >/dev/null; then
    case "$f" in
      */Services/Alerts/*) ;;
      *) report "$f" "AVAudioSession outside Services/Alerts (only the countdown feedback configures audio)" ;;
    esac
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "[privacy-check] OK (${#files[@]} file(s))"
fi
exit "$fail"
