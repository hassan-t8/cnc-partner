#!/usr/bin/env bash
#
# Build the signed Play release bundle (.aab) for CNC Partner.
#
#   ./scripts/build_release.sh                      # uses API_URL below
#   API_URL=https://api.example.com ./scripts/build_release.sh
#   ./scripts/build_release.sh --apk                # also build a test APK
#
# Requires android/key.properties (see scripts/make_upload_keystore.sh).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# The backend the shipped build talks to. Override per-build with the env var.
# lib/core/config/env.dart reads this via --dart-define=API_URL.
API_URL="${API_URL:-https://dev.api.crm.cnc.marifahlabs.com}"

BUILD_APK=0
[ "${1:-}" = "--apk" ] && BUILD_APK=1

if [ ! -f android/key.properties ]; then
  echo "ERROR: android/key.properties is missing — the bundle would be signed" >&2
  echo "with the debug key and Play would reject it." >&2
  echo "Run ./scripts/make_upload_keystore.sh first." >&2
  exit 1
fi

# The dev backend is currently the intended target, so this warns rather than
# blocks. Set ALLOW_DEV_API=1 to skip the prompt (required for non-interactive
# runs); unset it once a production host exists to get the confirmation back.
case "$API_URL" in
  *dev.*|*staging.*|*localhost*|*10.0.2.2*)
    echo
    echo "  ⚠️  API_URL is a NON-PRODUCTION host:"
    echo "      $API_URL"
    echo "      A build uploaded to Play will talk to this backend."
    echo
    if [ "${ALLOW_DEV_API:-0}" = "1" ]; then
      echo "  ALLOW_DEV_API=1 — continuing."
    elif [ -t 0 ]; then
      printf "  Continue anyway? [y/N] "
      read -r reply
      case "$reply" in [yY]*) ;; *) echo "Aborted."; exit 1 ;; esac
    else
      echo "  Refusing to build non-interactively. Set ALLOW_DEV_API=1 to override." >&2
      exit 1
    fi
    ;;
esac

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
echo "==> CNC Partner $VERSION"
echo "==> API_URL: $API_URL"
echo

flutter clean
flutter pub get
flutter build appbundle --release --dart-define=API_URL="$API_URL"

AAB="build/app/outputs/bundle/release/app-release.aab"

# Guard against a bundle that built fine but carries the debug certificate:
# Play rejects those at upload with a confusing error, so catch it here.
if command -v unzip >/dev/null && command -v keytool >/dev/null; then
  SIGNER="$(unzip -p "$AAB" META-INF/*.RSA 2>/dev/null \
    | keytool -printcert 2>/dev/null | grep -m1 "Owner:" || true)"
  case "$SIGNER" in
    *"Android Debug"*)
      echo "ERROR: the bundle is signed with the DEBUG certificate." >&2
      echo "Check android/key.properties." >&2
      exit 1 ;;
  esac
  [ -n "$SIGNER" ] && echo "==> Signed by: ${SIGNER#Owner: }"
fi

echo
echo "==> Bundle ready:"
echo "    $REPO_ROOT/$AAB"
echo "    $(du -h "$AAB" | cut -f1)"
echo
echo "Upload it at: Play Console → CNC Partner → Testing → Internal testing"
echo "              → Create new release → Upload"

if [ "$BUILD_APK" = "1" ]; then
  echo
  echo "==> Building a signed APK for sideload testing…"
  flutter build apk --release --dart-define=API_URL="$API_URL"
  echo "    $REPO_ROOT/build/app/outputs/flutter-apk/app-release.apk"
fi
