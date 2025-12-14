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
NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix-darwin}"
PROFILE_FILE="$NIX_CONFIG_DIR/.current-profile"
POLL_INTERVAL="${POLL_INTERVAL:-3600}"  # Default: 1 hour
LAUNCHD_LABEL="com.user.nix-darwin-update"
LAUNCHD_PLIST="$HOME/Library/LaunchAgents/$LAUNCHD_LABEL.plist"

get_current_profile() {
    if [[ -f "$PROFILE_FILE" ]]; then
        cat "$PROFILE_FILE"
    else
        echo "mini"  # Default profile
    fi
}

set_current_profile() {
    echo "$1" > "$PROFILE_FILE"
}

check_for_updates() {
    cd "$NIX_CONFIG_DIR"

    # Fetch latest changes
    git fetch origin

    # Check if there are new commits
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse @{u} 2>/dev/null || git rev-parse origin/main 2>/dev/null || git rev-parse origin/master)

    if [[ "$LOCAL" != "$REMOTE" ]]; then
        return 0  # Updates available
    else
        return 1  # No updates
    fi
}

apply_updates() {
    local profile
    profile=$(get_current_profile)

    cd "$NIX_CONFIG_DIR"

    log_info "Pulling latest changes..."
    git pull

    log_info "Rebuilding nix-darwin with profile: $profile"
    darwin-rebuild switch --flake ".#$profile"

    log_info "Update complete!"
}

run_update_check() {
    log_info "Checking for updates..."

    if ! [[ -d "$NIX_CONFIG_DIR" ]]; then
        log_error "Nix config directory not found: $NIX_CONFIG_DIR"
        log_error "Run bootstrap.sh first"
        exit 1
    fi

    if check_for_updates; then
        log_info "Updates available! Applying..."
        apply_updates
    else
        log_info "No updates available"
    fi
}

install_launchd() {
    local profile="${1:-$(get_current_profile)}"
    set_current_profile "$profile"

    log_info "Installing launchd agent for auto-updates..."
    log_info "Profile: $profile"
    log_info "Poll interval: ${POLL_INTERVAL}s"

    # Create LaunchAgents directory if needed
    mkdir -p "$HOME/Library/LaunchAgents"

    # Create the plist file
    cat > "$LAUNCHD_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCHD_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$NIX_CONFIG_DIR/update.sh</string>
        <string>--check</string>
    </array>
    <key>StartInterval</key>
    <integer>$POLL_INTERVAL</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/nix-darwin-update.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/nix-darwin-update.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>NIX_CONFIG_DIR</key>
        <string>$NIX_CONFIG_DIR</string>
    </dict>
</dict>
</plist>
EOF

    # Unload if already loaded
    launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true

    # Load the new plist
    launchctl load "$LAUNCHD_PLIST"

    log_info "Auto-update service installed and started"
    log_info "Logs: ~/Library/Logs/nix-darwin-update.log"
}

uninstall_launchd() {
    log_info "Uninstalling launchd agent..."

    if [[ -f "$LAUNCHD_PLIST" ]]; then
        launchctl unload "$LAUNCHD_PLIST" 2>/dev/null || true
        rm -f "$LAUNCHD_PLIST"
        log_info "Auto-update service removed"
    else
        log_warn "Launchd agent not found"
    fi
}

show_status() {
    echo "Nix Darwin Update Status"
    echo "========================="
    echo ""
    echo "Config directory: $NIX_CONFIG_DIR"
    echo "Current profile: $(get_current_profile)"
    echo ""

    if [[ -f "$LAUNCHD_PLIST" ]]; then
        echo "Auto-update: ENABLED"
        echo "Poll interval: ${POLL_INTERVAL}s"

        if launchctl list | grep -q "$LAUNCHD_LABEL"; then
            echo "Service status: RUNNING"
        else
            echo "Service status: NOT RUNNING"
        fi
    else
        echo "Auto-update: DISABLED"
    fi

    echo ""
    echo "Logs:"
    echo "  stdout: ~/Library/Logs/nix-darwin-update.log"
    echo "  stderr: ~/Library/Logs/nix-darwin-update.error.log"
}

usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  --check              Check for updates and apply if available"
    echo "  --install [profile]  Install launchd agent for auto-updates"
    echo "  --uninstall          Remove launchd agent"
    echo "  --status             Show current status"
    echo "  --set-profile NAME   Set the active profile (mini|develop)"
    echo "  --help               Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  NIX_CONFIG_DIR       Config directory (default: ~/.config/nix-darwin)"
    echo "  POLL_INTERVAL        Update check interval in seconds (default: 3600)"
}

# Main
case "${1:-}" in
    --check)
        run_update_check
        ;;
    --install)
        install_launchd "${2:-}"
        ;;
    --uninstall)
        uninstall_launchd
        ;;
    --status)
        show_status
        ;;
    --set-profile)
        if [[ -z "${2:-}" ]]; then
            log_error "Profile name required"
            exit 1
        fi
        if [[ "$2" != "mini" && "$2" != "develop" ]]; then
            log_error "Invalid profile: $2 (must be 'mini' or 'develop')"
            exit 1
        fi
        set_current_profile "$2"
        log_info "Profile set to: $2"
        ;;
    --help|-h|"")
        usage
        ;;
    *)
        log_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
