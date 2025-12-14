# nix-darwin

Nix-darwin configuration with three profiles: `mini`, `develop`, and `ios-builder`.

## Profiles

| Profile | Description |
|---------|-------------|
| `mini` | Minimal setup. Creates `mini` user, sets hostname to `mini-${serial_number}`. |
| `develop` | Extends mini with asdf. Auto-detects the single user in `/Users`. Preserves hostname. |
| `ios-builder` | For iOS CI/CD. Installs tart. Auto-detects user. Preserves hostname. |

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
/path/to/bootstrap-kandji.sh mini   # or develop
```

## Configuration Location

All configuration is stored in `/etc/nix-darwin/`:
- `flake.nix` - Main configuration
- `username.local` - Console user (for Homebrew)
- `hostname.local` - Hostname (mini profile only)
- `.current-profile` - Active profile

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
