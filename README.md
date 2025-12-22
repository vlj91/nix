# nix-darwin

Nix-darwin configuration with three profiles: `mini`, `develop`, and `ios-builder`.

## Profiles

| Profile | Description |
|---------|-------------|
| `mini` | Minimal setup. Creates `mini` user, sets hostname to `mini-${serial_number}`. Includes orchard controller. |
| `develop` | Extends mini with asdf. Auto-detects the single user in `/Users`. Preserves hostname. |
| `ios-builder` | For iOS CI/CD. Installs tart and orchard worker. Auto-detects user. Preserves hostname. Requires orchard configuration. |

## Bootstrap

### Manual (with sudo)

```bash
curl -fsSL https://raw.githubusercontent.com/vlj91/nix/main/bootstrap.sh -o /tmp/bootstrap.sh
sudo bash /tmp/bootstrap.sh mini    # or develop
```

### Via Kandji

Upload `bootstrap-kandji.sh` to Kandji and configure it to run as a Custom Script.

```bash
# Kandji will run as root and detect the console user automatically
/path/to/bootstrap-kandji.sh mini   # or develop, or ios-builder
```

**For detailed Kandji blueprint setup instructions, see [KANDJI.md](./KANDJI.md)**

## Configuration Location

All configuration is stored in `/etc/nix-darwin/`:
- `flake.nix` - Main configuration
- `username.local` - Console user (for Homebrew)
- `hostname.local` - Hostname (mini profile only)
- `orchard-token.local` - Orchard bootstrap token (ios-builder profile only, **not committed to git**)
- `orchard-controller.local` - Orchard controller hostname (ios-builder profile only, **not committed to git**)
- `.current-profile` - Active profile

### iOS Builder Configuration

The `ios-builder` profile requires additional secret configuration files and Tailscale setup:

#### 1. Orchard Secrets

```bash
# Create orchard bootstrap token file
echo "your-bootstrap-token-here" | sudo tee /etc/nix-darwin/orchard-token.local
sudo chmod 600 /etc/nix-darwin/orchard-token.local

# Create orchard controller hostname file
echo "your-controller-hostname.example.com" | sudo tee /etc/nix-darwin/orchard-controller.local
sudo chmod 600 /etc/nix-darwin/orchard-controller.local
```

These files are git-ignored and must be created before bootstrapping with the `ios-builder` profile.

#### 2. Tailscale Authentication

The orchard worker requires Tailscale to be connected (since the controller is typically on the Tailscale network). Create an ephemeral auth key file:

```bash
# Create Tailscale auth key directory
sudo mkdir -p /etc/tailscale/keys

# Store ephemeral auth key (get from Tailscale admin console)
echo "tskey-auth-xxxxx-xxxxx" | sudo tee /etc/tailscale/keys/ephemeral
sudo chmod 600 /etc/tailscale/keys/ephemeral
```

The orchard worker service will automatically wait for Tailscale to connect before starting (up to 5 minutes).

## Auto-updates

Enable automatic updates (polls git remote hourly):

```bash
sudo /etc/nix-darwin/update.sh --install
```

Other commands:

```bash
sudo /etc/nix-darwin/update.sh --check        # Check and apply updates now
/etc/nix-darwin/update.sh --status            # Show status
sudo /etc/nix-darwin/update.sh --uninstall    # Disable auto-updates
```

Logs: `/var/log/nix-darwin-update.log`

## Manual rebuild

```bash
sudo darwin-rebuild switch --flake /etc/nix-darwin#mini
# or
sudo darwin-rebuild switch --flake /etc/nix-darwin#develop
```

## Adding Homebrew packages

Packages can be added declaratively in `modules/common.nix`:

```nix
homebrew = {
  brews = [ "awscli" ];
  casks = [ "firefox" ];
};
```

Or installed manually with `brew install` - manual installs are preserved.
