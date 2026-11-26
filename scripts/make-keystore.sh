#!/usr/bin/env bash
# Makes the release signing key for the AksharSevak Android app, once, and prints the four values to add as GitHub secrets.
# Run it in Cloud Shell. Nothing is sent anywhere. KEEP THE KEYSTORE FILE SAFE (Drive, a password manager): if it is lost,
# installed phones can never be updated again and everyone must uninstall and install afresh.
set -euo pipefail
OUT="${1:-$HOME/aksharsevak-release.jks}"
[ -e "$OUT" ] && { echo "$OUT already exists. Not overwriting it."; exit 1; }
PASS="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
keytool -genkeypair -v -keystore "$OUT" -storetype JKS -keyalg RSA -keysize 2048 -validity 36500 \
  -alias aksharsevak -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=AksharSevak, OU=Mobile, O=Maxpro Infotech, C=KE" >/dev/null
echo
echo "Keystore written to: $OUT   (keep a copy somewhere safe)"
echo
echo "Add these four secrets at https://github.com/abtpltd/AksharSevaApp/settings/secrets/actions"
echo
echo "ANDROID_KEYSTORE_PASSWORD = $PASS"
echo "ANDROID_KEY_ALIAS         = aksharsevak"
echo "ANDROID_KEY_PASSWORD      = $PASS"
echo "ANDROID_KEYSTORE_BASE64   = (the long text below)"
base64 -w0 "$OUT"; echo
