#!/bin/bash
set -e

# Kandji bootstrap script - runs as root

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
REPO_URL="${REPO_URL:-https://github.com/vlj91/nix.git}"
NIX_CONFIG_DIR="/etc/nix-darwin"
PROFILE="${1:-mini}"

# Validate profile
if [[ "$PROFILE" != "mini" && "$PROFILE" != "develop" && "$PROFILE" != "ios-builder" ]]; then
    log_error "Invalid profile: $PROFILE"
    echo "Usage: $0 [mini|develop|ios-builder]"
    exit 1
fi

# Ensure running as root (Kandji requirement)
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Get the console user (the actual logged-in user)
get_console_user() {
    local console_user
    console_user=$(scutil <<< "show State:/Users/ConsoleUser" | awk '/Name :/ { print $3 }')

    if [[ -z "$console_user" || "$console_user" == "loginwindow" || "$console_user" == "_mbsetupuser" ]]; then
        return 1
    fi

    echo "$console_user"
}

# Find the single user in /Users for develop profile
find_single_user() {
    local users
    users=$(ls -1 /Users | grep -v "^Shared$" | grep -v "^\." | grep -v "^Guest$")
    local user_count
    user_count=$(echo "$users" | wc -l | tr -d ' ')

    if [[ "$user_count" -eq 1 ]]; then
        echo "$users"
        return 0
    fi
    return 1
}

# Wait for a user to be logged in (only needed for develop profile)
wait_for_console_user() {
    local max_attempts=60
    local attempt=0

    log_info "Waiting for console user..."

    while [[ $attempt -lt $max_attempts ]]; do
        if CONSOLE_USER=$(get_console_user); then
            log_info "Console user detected: $CONSOLE_USER"
            return 0
        fi
        sleep 5
        ((attempt++))
    done

    log_error "Timed out waiting for console user"
    return 1
}

# Main
log_info "Kandji bootstrap starting with profile: $PROFILE"

# Determine target user - find single user or wait for console user
if TARGET_USER=$(find_single_user); then
    log_info "Found single user: $TARGET_USER"
elif wait_for_console_user; then
    TARGET_USER="$CONSOLE_USER"
else
    log_error "Could not determine user for $PROFILE profile"
    exit 1
fi

log_info "Target user: $TARGET_USER"

# Install Xcode Command Line Tools if not present
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."

    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    CLT_PACKAGE=$(softwareupdate -l 2>/dev/null | \
        grep -B 1 "Command Line Tools" | \
        awk -F"*" '/^ *\*/ {print $2}' | \
        sed 's/^ *Label: //' | \
        head -n1)

    if [[ -n "$CLT_PACKAGE" ]]; then
        log_info "Installing: $CLT_PACKAGE"
        softwareupdate -i "$CLT_PACKAGE" --verbose
    else
        log_error "Could not find Command Line Tools package"
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        exit 1
    fi

    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    if ! xcode-select -p &>/dev/null; then
        log_error "Xcode Command Line Tools installation failed"
        exit 1
    fi

    log_info "Xcode Command Line Tools installed successfully"
fi

# Install Nix if not present
if ! command -v nix &>/dev/null && [[ ! -d /nix ]]; then
    log_info "Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
        sh -s -- install --no-confirm
    log_info "Nix installed successfully"
else
    log_info "Nix is already installed"
fi

# Source nix
for profile in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
               /etc/profile.d/nix.sh; do
    if [[ -f "$profile" ]]; then
        . "$profile"
        break
    fi
done
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

if ! command -v nix &>/dev/null; then
    log_error "Nix command not found after installation. Bootstrap failed."
    exit 1
fi

# Clone or update config repository
if [[ -d "$NIX_CONFIG_DIR/.git" ]]; then
    log_info "Updating existing nix-darwin configuration..."
    git -C "$NIX_CONFIG_DIR" pull origin main || git -C "$NIX_CONFIG_DIR" pull origin master || true
else
    log_info "Cloning nix-darwin configuration..."
    rm -rf "$NIX_CONFIG_DIR"
    git clone "$REPO_URL" "$NIX_CONFIG_DIR"
fi

# Generate local configuration
log_info "Generating local configuration..."

echo "$TARGET_USER" > "$NIX_CONFIG_DIR/username.local"
log_info "Username: $TARGET_USER"

if [[ "$PROFILE" == "mini" ]]; then
    SERIAL_NUMBER=$(ioreg -l | grep IOPlatformSerialNumber | cut -d'"' -f4)
    HOSTNAME="mini-${SERIAL_NUMBER}"
    echo "$HOSTNAME" > "$NIX_CONFIG_DIR/hostname.local"
    log_info "Hostname: $HOSTNAME"
fi

echo "$PROFILE" > "$NIX_CONFIG_DIR/.current-profile"

# Build and switch
log_info "Building and activating nix-darwin configuration..."
cd "$NIX_CONFIG_DIR"

if ! command -v darwin-rebuild &>/dev/null; then
    log_info "First time setup - bootstrapping nix-darwin..."
    nix run nix-darwin -- switch --flake ".#$PROFILE"
else
    darwin-rebuild switch --flake ".#$PROFILE"
fi

log_info "Kandji bootstrap complete!"
log_info "Profile '$PROFILE' activated for user '$TARGET_USER'"
