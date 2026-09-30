#!/bin/bash
set -e

# ==========================================
# SwitchFix User-Friendly Installer
# ==========================================
#
# Usage: ./install.sh [--reset-permissions]
#   --reset-permissions  reset SwitchFix's Accessibility and Input Monitoring
#                        grants and walk through granting them again

RESET_PERMISSIONS_REQUESTED=false
for arg in "$@"; do
    case "$arg" in
        --reset-permissions) RESET_PERMISSIONS_REQUESTED=true ;;
        *) echo "Unknown option: $arg (usage: ./install.sh [--reset-permissions])" >&2; exit 2 ;;
    esac
done

echo "=========================================="
echo "      Welcome to SwitchFix Setup!         "
echo "=========================================="
echo ""
echo "This script will:"
echo " 1. Build the app from source"
echo " 2. Install it to your Applications folder"
echo " 3. Set it to automatically start at login"
echo " 4. Guide you through the privacy permissions"
echo ""
sleep 2

# 1. Check for Swift (Xcode Command Line Tools)
if ! command -v swift &> /dev/null; then
    echo "⚠️ Apple's Command Line Tools are required to build SwitchFix."
    echo "A system prompt should appear to install them. Please follow the instructions, and then run this script again."
    xcode-select --install
    exit 1
fi

# 2. Build the app
echo "🚀 Step 1: Building SwitchFix..."
if [ -f "./scripts/build-app.sh" ]; then
    ./scripts/build-app.sh
else
    echo "❌ Error: Could not find scripts/build-app.sh. Make sure you are running this from the root of the SwitchFix repository."
    exit 1
fi

# 3. Install to /Applications
echo ""
echo "📦 Step 2: Installing to Applications folder..."

APP_WAS_INSTALLED=false
if [ -d "/Applications/SwitchFix.app" ]; then
    APP_WAS_INSTALLED=true
fi

APP_WAS_RUNNING=0
if pgrep -x "SwitchFixApp" > /dev/null; then
    APP_WAS_RUNNING=1
    echo "Stopping currently running SwitchFixApp..."
    pkill -x "SwitchFixApp" || true
    sleep 1
fi

if [ -d "/Applications/SwitchFix.app" ]; then
    echo "Removing older version from /Applications..."
    rm -rf "/Applications/SwitchFix.app"
fi
cp -R "./dist/SwitchFix.app" "/Applications/"
echo "✅ Installed to /Applications/SwitchFix.app"

# 4. Add to Startup (Login Items)
echo ""
echo "🔄 Step 3: Setting up 'Start at Login'..."
# Remove any existing login item to avoid duplicates (ignoring errors if it doesn't exist)
osascript -e 'tell application "System Events" to delete login item "SwitchFix"' > /dev/null 2>&1 || true
# Add the new login item
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/SwitchFix.app", hidden:false}' > /dev/null 2>&1
echo "✅ SwitchFix has been added to your startup items."

# 5. Handle Permissions
echo ""

# Decide whether to walk through permission setup (which resets SwitchFix's
# TCC entries first, so a grant bound to an older signature cannot linger):
#  - ad-hoc signed builds always need a fresh grant,
#  - certificate-signed builds keep their grants across rebuilds, so the
#    walkthrough runs only when SwitchFix was not in /Applications before, or
#    with --reset-permissions. This used to be a y/N prompt, and
#    `yes | ./install.sh` silently wiped Accessibility on every reinstall.
# The signature is read from the installed app: build-app.sh falls back to
# ad-hoc when the identity in .codesign-identity is missing from the keychain.
NEEDS_PERMISSION_SETUP=false
if [ "$RESET_PERMISSIONS_REQUESTED" = true ] || [ "$APP_WAS_INSTALLED" = false ]; then
    NEEDS_PERMISSION_SETUP=true
elif ! codesign -dvv "/Applications/SwitchFix.app" 2>&1 | grep -q '^Authority='; then
    NEEDS_PERMISSION_SETUP=true
fi

if [ "$NEEDS_PERMISSION_SETUP" = true ]; then
    echo "🛡️ Step 4: Setting up macOS Permissions..."
    echo "SwitchFix intercepts keyboard input to fix layouts, so macOS requires you to grant it explicit permissions."
    echo ""

    # Drop TCC entries bound to an older signature so the new grant sticks
    tccutil reset Accessibility com.switchfix.app >/dev/null 2>&1 || true
    tccutil reset ListenEvent com.switchfix.app >/dev/null 2>&1 || true

    # Open Accessibility settings & Finder
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
    open -R "/Applications/SwitchFix.app"

    cat <<EOF
══════════════════════════════════════════════════════════════════
  Action Required (Step 1/2: Accessibility):
  1. In the "Accessibility" settings window that just opened:
     - Enable the toggle for "SwitchFix".
     - If SwitchFix is not in the list, drag "SwitchFix.app"
       from the opened Finder window into the list.
══════════════════════════════════════════════════════════════════
EOF

    read -p "Press [Enter] after enabling Accessibility to continue to Input Monitoring... "

    open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent" || true

    cat <<EOF

══════════════════════════════════════════════════════════════════
  Action Required (Step 2/2: Input Monitoring):
  2. In the "Input Monitoring" settings window:
     - Enable the toggle for "SwitchFix" (or drag SwitchFix.app in).
══════════════════════════════════════════════════════════════════
EOF

    read -p "Press [Enter] when done to launch SwitchFix... "

    echo ""
    echo "🚀 Launching SwitchFix..."
    open "/Applications/SwitchFix.app"
else
    echo "✅ Signed with stable certificate — permissions survive rebuilds."
    echo "   Your existing Accessibility and Input Monitoring grants are kept."
    echo "   If they are missing, run ./install.sh --reset-permissions."
    echo ""
    echo "🚀 Launching SwitchFix..."
    open "/Applications/SwitchFix.app"
fi

echo ""
echo "🎉 Setup Complete! SwitchFix is now installed and running."
echo ""
echo "💡 Quick Test:"
echo "   Switch your keyboard layout to English and type 'ghbdtn ' (with Space)."
echo "   SwitchFix will automatically convert it to 'привіт ' / 'привет ' and switch your layout."
echo ""
echo "📋 To watch live debug logs, run:"
echo "   log stream --level debug --style compact --predicate 'subsystem == \"com.switchfix\"'"
echo ""
