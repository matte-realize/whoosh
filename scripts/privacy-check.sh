#!/usr/bin/env bash
# Enforces the rules in .kiro/steering/privacy.md and the layering table in the specs
# (ride-recording-mvp design + crash-response design "Privacy and network invariants"
# + watch-companion design "Privacy and network invariants").
# Usage: scripts/privacy-check.sh <file.swift> [more files...]
# With no arguments, checks every Swift file under Whoosh/, WhooshWatch/, and
# Packages/WhooshWire/Sources/.
# Exits 1 and prints violations if any rule is broken; exits 0 otherwise.
#
# MVP rules (unchanged): 1 network only in Services/Sync, 2 no analytics SDKs,
# 3 no secrets, 4 honest copy, 5 Models/Metrics import Foundation only,
# 6 Views never touch CoreLocation/SwiftData.
# Crash-response additions: network also allowed in Services/Notification; provider
# credentials flagged anywhere; tel:/telprompt: only in Features/Emergency; MessageUI
# only in Support/Representables; CoreMotion only in Services/Crash (and Services/Camera,
# see below); Keychain SecItem only in Services/Contacts; AVAudioSession only in
# Services/Alerts; and copy that claims emergency services were notified or that help
# is on the way.
# Rear-camera additions (replaces the old rule 7 "camera only in Services/Detection"):
# 7 capture/writer APIs (AVCaptureSession, AVCaptureDevice, AVCaptureVideoDataOutput,
#   AVCaptureAudioDataOutput, AVCaptureMovieFileOutput, AVAssetWriter, camera/microphone
#   requestAccess) only in Services/Camera/ — the detectors consume frames, they do not
#   capture, so Services/Detection is no longer allowed.
# 10 CoreMotion also allowed in Services/Camera/ (mount level sensor) in addition to
#   Services/Crash.
# 13 import Photos / PHPhotoLibrary only in Services/Camera/PhotosClipExporter.swift.
# 14 import WatchConnectivity only in Whoosh/Services/Remote/WCSessionWireLink.swift and
#   WhooshWatch/Services/Link/ (the only WatchConnectivity adapters, phone and watch).
# 15 UIScreen brightness writes and isIdleTimerDisabled only in Services/Screen/
#   (ActiveRideView's idle timer is migrated behind the ScreenController, task 21).
# 16 files under Services/Sync/ and Services/Notification/ must not reference camera,
#   clip, or footage types (VideoFrame, ClipRecord, SegmentInfo, FootageBuffer, AVAsset,
#   .mp4/.mov).
# 17 Models/Metrics must not import AVFoundation, CoreMedia, CoreVideo, Photos, or
#   CoreMotion (extends rule 5).
# 18 honest copy: footage is for the rider's own records, never "evidence" and never a
#   claim that capture is assured ("cannot guarantee detection or delivery").
# Watch-companion additions (the watch is phone-authoritative; nothing leaves the user's
# devices; see watch-companion design "Privacy and network invariants", amendment A10):
# 19 the shared package (Packages/WhooshWire/Sources) is Foundation-only, like
#   Models/Metrics (extends rules 5 and 17): no SwiftUI/WatchKit/HealthKit/
#   WatchConnectivity/CoreLocation/MapKit/AVFoundation/Photos/CoreMotion/networking.
# 20 import HealthKit / HKWorkoutSession / HKHealthStore only in
#   WhooshWatch/Services/Workout/ and the single phone file that calls startWatchApp
#   (Whoosh/Services/Remote/WatchLauncher.swift).
# 21 WatchKit haptic calls (WKInterfaceDevice.play / WKHapticType) only in
#   WhooshWatch/Services/Haptics/.
# 22 WhooshWatch/ imports no CoreLocation, MapKit, AVFoundation, AVKit, CoreMedia,
#   CoreVideo, Photos, or networking/analytics API (the watch holds no ride data, no
#   route, no video, and makes no network request).
# 23 the network layers (Services/Sync, Services/Notification) must not reference wire
#   types (WireEnvelope/WireRideStatus/WireAlert/WireCommand/WireCommandReply/
#   WireWatchState/WireHello/WireSummary/WireAlertReceipt): the wire contract is device
#   to device and never crosses the network boundary.
set -o pipefail  # no -u: macOS bash 3.2 errors on empty arrays
cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(find Whoosh WhooshWatch Packages/WhooshWire/Sources -name '*.swift' 2>/dev/null)
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

  # 5. Layering: Models and Metrics import Foundation only (extended for the camera
  #    spec: also no AVFoundation/CoreMedia/CoreVideo/Photos/CoreMotion/WatchConnectivity;
  #    extended for the watch spec (rule 19): the shared package Packages/WhooshWire/Sources
  #    is Foundation-only too, and HealthKit/WatchKit are also forbidden here — time is a
  #    TimeInterval/Date, never a CMTime).
  case "$f" in
    */Models/*|*/Metrics/*|Packages/WhooshWire/Sources/*)
      if grep -nE '^import (SwiftUI|CoreLocation|SwiftData|MapKit|UIKit|WatchKit|HealthKit|AVFoundation|AVKit|CoreMedia|CoreVideo|Photos|PhotosUI|CoreMotion|MessageUI|ContactsUI|WatchConnectivity)' "$f" >/dev/null; then
        report "$f" "Models/Metrics/WhooshWire package must import Foundation only (rule 5/19)"
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

  # 7. Capture and asset-writer APIs only in Services/Camera (the only AVCaptureSession
  #    owner and the only asset writer). Detectors consume frames; they never capture.
  if grep -nE 'AVCaptureSession|AVCaptureDevice|AVCaptureVideoDataOutput|AVCaptureAudioDataOutput|AVCaptureMovieFileOutput|AVAssetWriter|(AVCaptureDevice|AVCaptureDeviceInput)\.requestAccess|requestAccess\(for: ?\.(video|audio)\)' "$f" >/dev/null; then
    case "$f" in
      */Services/Camera/*) ;;
      *) report "$f" "capture/writer API outside Services/Camera (only the camera service owns capture and the asset writer; detectors consume frames)" ;;
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

  # 10. Core Motion only where motion is consumed: the crash detector (Services/Crash)
  #     and the rear-camera mount level sensor (Services/Camera).
  if grep -nE 'import CoreMotion|CMMotionManager|CMMotionActivityManager' "$f" >/dev/null; then
    case "$f" in
      */Services/Crash/*) ;;
      */Services/Camera/*) ;;
      *) report "$f" "CoreMotion outside Services/Crash and Services/Camera (only the crash detector and the mount level sensor read motion)" ;;
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

  # 13. Photos export only in the single export file; footage leaves the camera folder
  #     only on an explicit, add-only Photos save.
  if grep -nE 'import Photos|import PhotosUI|PHPhotoLibrary|PHAssetCreationRequest' "$f" >/dev/null; then
    case "$f" in
      */Services/Camera/PhotosClipExporter.swift) ;;
      *) report "$f" "Photos API outside Services/Camera/PhotosClipExporter.swift (clip export is the only Photos path, add-only, on explicit rider action)" ;;
    esac
  fi

  # 14. WatchConnectivity only in the two named adapters: the phone wire link
  #     (Whoosh/Services/Remote/WCSessionWireLink.swift) and the watch link folder
  #     (WhooshWatch/Services/Link/). Nothing else may import it.
  if grep -nE 'import WatchConnectivity|WCSession' "$f" >/dev/null; then
    case "$f" in
      */Whoosh/Services/Remote/WCSessionWireLink.swift) ;;
      Whoosh/Services/Remote/WCSessionWireLink.swift) ;;
      */WhooshWatch/Services/Link/*) ;;
      WhooshWatch/Services/Link/*) ;;
      *) report "$f" "WatchConnectivity outside Whoosh/Services/Remote/WCSessionWireLink.swift and WhooshWatch/Services/Link/ (the only WatchConnectivity adapters)" ;;
    esac
  fi

  # 15. Screen brightness writes and the idle-timer toggle only in Services/Screen
  #     (the only code that dims the screen / keeps it awake). ActiveRideView is
  #     temporarily allowed until task 21 migrates its idle-timer call behind the
  #     ScreenController.
  if grep -nE '\.brightness *=|isIdleTimerDisabled' "$f" >/dev/null; then
    case "$f" in
      */Services/Screen/*) ;;
      *) report "$f" "screen brightness write / isIdleTimerDisabled outside Services/Screen (ride mode and the idle timer are owned by the screen controller)" ;;
    esac
  fi

  # 16. The network layers must never reference camera, clip, or footage types: footage
  #     never leaves the device and is never uploaded, linked, or put in a message.
  case "$f" in
    */Services/Sync/*|*/Services/Notification/*)
      if grep -nE 'VideoFrame|ClipRecord|ClipReason|SegmentInfo|SegmentRecord|FootageBuffer|ClipFootageBuffer|AVAsset|\.mp4|\.mov' "$f" >/dev/null; then
        report "$f" "camera/clip/footage reference in a network layer (Services/Sync, Services/Notification): footage never leaves the device"
      fi
      ;;
  esac

  # 18. Honest copy: never call footage "evidence" or claim capture is assured. Phrased
  #     to avoid colliding with rule 4 (which already covers collision prevention).
  if grep -nEi '(footage|video|recording|clip)[a-z ]* (is|as|are|provides?|serves? as) [a-z ]*evidence' "$f" >/dev/null; then
    report "$f" "copy calls footage evidence (recording is for the rider's own records; cannot guarantee detection or delivery)"
  fi
  if grep -nEi '(guarantee|ensure|assured?|always) (that )?[a-z ]*(the )?(incident|crash|vehicle|hazard|moment|footage) [a-z ]*(is |will be |was )?(captured|recorded)' "$f" >/dev/null; then
    report "$f" "copy claims capture is assured (cannot guarantee detection or delivery; recording may fail)"
  fi

  # 20. HealthKit / workout-session APIs only on the watch, in the workout folder, and in
  #     the single phone file that calls startWatchApp (the phone never holds a session;
  #     it only asks the system to launch the watch app). The write-only workout keep-alive
  #     is the sole HealthKit use (watch-companion Req 4, 19.5).
  if grep -nE 'import HealthKit|HKWorkoutSession|HKWorkoutConfiguration|HKLiveWorkoutBuilder|HKHealthStore' "$f" >/dev/null; then
    case "$f" in
      */WhooshWatch/Services/Workout/*) ;;
      WhooshWatch/Services/Workout/*) ;;
      */Whoosh/Services/Remote/WatchLauncher.swift) ;;
      Whoosh/Services/Remote/WatchLauncher.swift) ;;
      *) report "$f" "HealthKit/HKWorkoutSession outside WhooshWatch/Services/Workout/ and Whoosh/Services/Remote/WatchLauncher.swift (the workout keep-alive and the single startWatchApp caller are the only HealthKit users)" ;;
    esac
  fi

  # 21. WatchKit haptic playback only in the watch haptics folder (the single haptic
  #     actuator; the limiter/selector are pure in the package). Only the haptic
  #     *playback* call (`WKInterfaceDevice...play(`) and `WKHapticType` are confined;
  #     other `WKInterfaceDevice` uses (e.g. battery monitoring for WireWatchState in
  #     the workout keep-alive) are not haptic calls and are allowed.
  if grep -nE 'WKInterfaceDevice[^\n]*\.play\(|\.play\(\.[A-Za-z]|\bWKHapticType\b' "$f" >/dev/null; then
    case "$f" in
      */WhooshWatch/Services/Haptics/*) ;;
      WhooshWatch/Services/Haptics/*) ;;
      *) report "$f" "WatchKit haptic call (WKInterfaceDevice.play/WKHapticType) outside WhooshWatch/Services/Haptics/ (haptics have one actuator; selection and limiting are pure in the package)" ;;
    esac
  fi

  # 22. The watch target holds no ride data, no route, no video, and makes no network
  #     request: WhooshWatch/ must not import CoreLocation, MapKit, AVFoundation/AVKit,
  #     CoreMedia, CoreVideo, Photos, or any networking API (watch-companion Req 19.3, 19.9).
  case "$f" in
    */WhooshWatch/*|WhooshWatch/*)
      if grep -nE '^import (CoreLocation|MapKit|AVFoundation|AVKit|CoreMedia|CoreVideo|Photos|PhotosUI)' "$f" >/dev/null; then
        report "$f" "WhooshWatch imports a forbidden framework (CoreLocation/MapKit/AVFoundation/CoreMedia/CoreVideo/Photos): the watch holds no route, video, or location"
      fi
      if grep -nE 'URLSession|URLRequest|import Supabase|WKWebView|import Network' "$f" >/dev/null; then
        report "$f" "WhooshWatch uses a network API (the watch app makes no network request; WatchConnectivity is device to device)"
      fi
      ;;
  esac

  # 23. The network layers must never reference wire types: the wire contract is device to
  #     device over WatchConnectivity and never crosses the network boundary.
  case "$f" in
    */Services/Sync/*|*/Services/Notification/*)
      if grep -nE 'WireEnvelope|WireRideStatus|WireAlert|WireCommand|WireCommandReply|WireWatchState|WireHello|WireSummary|WireAlertReceipt' "$f" >/dev/null; then
        report "$f" "wire type referenced in a network layer (Services/Sync, Services/Notification): the wire contract is device to device, never uploaded"
      fi
      ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "[privacy-check] OK (${#files[@]} file(s))"
fi
exit "$fail"
