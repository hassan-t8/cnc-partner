#!/usr/bin/env bash
#
# Create the Play upload keystore for CNC Partner and write android/key.properties.
#
# Run this ONCE. The keystore it produces is the only thing that lets you ship
# updates to the published app — if you lose it you cannot update the listing
# without asking Google to reset the upload key. Back it up off this machine.
#
#   ./scripts/make_upload_keystore.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE_DIR="${KEYSTORE_DIR:-$HOME/keystores}"
KEYSTORE="$KEYSTORE_DIR/carenclean-upload.jks"
ALIAS="${ALIAS:-partner}"
PROPS="$REPO_ROOT/android/key.properties"

command -v keytool >/dev/null || {
  echo "keytool not found. Install a JDK (e.g. the one bundled with Android Studio)." >&2
  exit 1
}

mkdir -p "$KEYSTORE_DIR"
chmod 700 "$KEYSTORE_DIR"

if [ -f "$KEYSTORE" ] && keytool -list -keystore "$KEYSTORE" -alias "$ALIAS" >/dev/null 2>&1; then
  echo "Alias '$ALIAS' already exists in $KEYSTORE — not regenerating."
  echo "Delete the alias first if you really want a new key."
  exit 1
fi

echo "Creating upload key '$ALIAS' in $KEYSTORE"
echo

if [ -n "${KEYSTORE_PASSWORD:-}" ]; then
  # Non-interactive path (also used when a generated password is piped in).
  STORE_PASS="$KEYSTORE_PASSWORD"
  [ "${#STORE_PASS}" -ge 6 ] || { echo "Password must be at least 6 characters." >&2; exit 1; }
elif [ -t 0 ]; then
  echo "Pick a strong password (min 6 chars). You will need it for every release,"
  echo "so store it in your password manager now — it is not recoverable."
  echo
  read -rsp "Keystore password: " STORE_PASS; echo
  read -rsp "Confirm password:  " STORE_PASS2; echo
  [ "$STORE_PASS" = "$STORE_PASS2" ] || { echo "Passwords do not match." >&2; exit 1; }
  [ "${#STORE_PASS}" -ge 6 ] || { echo "Password must be at least 6 characters." >&2; exit 1; }
else
  echo "No TTY and KEYSTORE_PASSWORD is unset — cannot read a password." >&2
  exit 1
fi

# One password for both the store and the key keeps Gradle config simple.
keytool -genkeypair \
  -keystore "$KEYSTORE" \
  -alias "$ALIAS" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storetype JKS \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=Carencleanss, OU=Mobile, O=Carencleanss, L=Dubai, C=AE"

chmod 600 "$KEYSTORE"

umask 077
cat > "$PROPS" <<EOF
storeFile=$KEYSTORE
storePassword=$STORE_PASS
keyAlias=$ALIAS
keyPassword=$STORE_PASS
EOF
chmod 600 "$PROPS"

echo
echo "Done."
echo "  keystore : $KEYSTORE"
echo "  config   : $PROPS  (gitignored)"
echo
echo "SHA-1 / SHA-256 of the upload key — add the SHA-1 to Firebase if this app"
echo "uses Google Sign-In:"
keytool -list -v -keystore "$KEYSTORE" -alias "$ALIAS" -storepass "$STORE_PASS" \
  | grep -E "SHA1|SHA256"
echo
echo "BACK UP $KEYSTORE and the password somewhere off this Mac."
