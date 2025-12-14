#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configuration
REPO_URL="${REPO_URL:-https://github.com/vlj91/nix.git}"
NIX_CONFIG_DIR="/etc/nix-darwin"

# Parse arguments
PROFILE="${1:-mini}"

if [[ "$PROFILE" != "mini" && "$PROFILE" != "develop" && "$PROFILE" != "ios-builder" ]]; then
    log_error "Invalid profile: $PROFILE"
    echo "Usage: $0 [mini|develop|ios-builder]"
    exit 1
fi

log_info "Bootstrapping macOS with profile: $PROFILE"

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script only runs on macOS"
    exit 1
fi

# Check for root/sudo for system directory access
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "This script requires root privileges. Run with sudo."
    exit 1
fi

# Determine the target user - find the single user in /Users
determine_user() {
    local users
    users=$(ls -1 /Users | grep -v "^Shared$" | grep -v "^\." | grep -v "^Guest$")
    local user_count
    user_count=$(echo "$users" | wc -l | tr -d ' ')

    if [[ "$user_count" -eq 1 ]]; then
        echo "$users"
    elif [[ -n "$SUDO_USER" ]]; then
        echo "$SUDO_USER"
    else
        log_error "Could not determine user for $PROFILE profile"
        log_error "Found users: $users"
        exit 1
    fi
}

ACTUAL_USER=$(determine_user)
log_info "Configuring for user: $ACTUAL_USER"

# Install Xcode Command Line Tools if not present (non-interactive)
if ! xcode-select -p &>/dev/null; then
    log_info "Installing Xcode Command Line Tools..."

    # Trigger the install request
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    # Find the latest Command Line Tools package
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

    # Verify installation
    if ! xcode-select -p &>/dev/null; then
        log_error "Xcode Command Line Tools installation failed"
        exit 1
    fi

    log_info "Xcode Command Line Tools installed successfully"
fi

# Install Nix if not present (non-interactive)
if ! command -v nix &>/dev/null; then
    log_info "Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
        sh -s -- install --no-confirm

    # Source nix
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    log_info "Nix installed successfully"
else
    log_info "Nix is already installed"
fi

# Ensure nix is available in current shell
if ! command -v nix &>/dev/null; then
    # Try common nix profile locations
    for profile in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh \
                   /etc/profile.d/nix.sh \
                   "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
        if [[ -f "$profile" ]]; then
            . "$profile"
            break
        fi
    done

    # Also add to PATH directly as fallback
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi

# Final check
if ! command -v nix &>/dev/null; then
    log_error "Nix command not found after installation. Bootstrap failed."
    exit 1
fi

# Clone or update the nix config repository
if [[ -d "$NIX_CONFIG_DIR/.git" ]]; then
    log_info "Updating existing nix-darwin configuration..."
    git -C "$NIX_CONFIG_DIR" pull origin main || git -C "$NIX_CONFIG_DIR" pull origin master || true
else
    log_info "Cloning nix-darwin configuration..."
    rm -rf "$NIX_CONFIG_DIR"
    git clone "$REPO_URL" "$NIX_CONFIG_DIR"
fi

# Generate local configuration files
log_info "Generating local configuration..."

# Save current username for nix-homebrew
echo "$ACTUAL_USER" > "$NIX_CONFIG_DIR/username.local"
log_info "Username: $ACTUAL_USER"

# Generate hostname.local for mini profile
if [[ "$PROFILE" == "mini" ]]; then
    log_info "Generating hostname for mini profile..."
    SERIAL_NUMBER=$(ioreg -l | grep IOPlatformSerialNumber | cut -d'"' -f4)
    HOSTNAME="mini-${SERIAL_NUMBER}"
    echo "$HOSTNAME" > "$NIX_CONFIG_DIR/hostname.local"
    log_info "Hostname will be set to: $HOSTNAME"
fi

# Save current profile
echo "$PROFILE" > "$NIX_CONFIG_DIR/.current-profile"

# Build and switch to the configuration
log_info "Building and activating nix-darwin configuration..."

cd "$NIX_CONFIG_DIR"

# First time setup - need to bootstrap nix-darwin
if ! command -v darwin-rebuild &>/dev/null; then
    log_info "First time setup - bootstrapping nix-darwin..."
    nix run nix-darwin -- switch --flake ".#$PROFILE"
else
    darwin-rebuild switch --flake ".#$PROFILE"
fi

# Install auto-update daemon
log_info "Installing auto-update daemon..."
"$NIX_CONFIG_DIR/update.sh" --install "$PROFILE"

log_info "Bootstrap complete!"
log_info "Profile '$PROFILE' has been activated."
log_info ""
log_info "Next steps:"
log_info "  1. Restart your terminal to apply shell changes"
log_info "  2. Run 'sudo darwin-rebuild switch --flake /etc/nix-darwin#$PROFILE' to apply future changes"
