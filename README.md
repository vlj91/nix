# nix-darwin

Nix-darwin configuration with two profiles: `mini` and `develop`.

## Profiles

| Profile | Description |
|---------|-------------|
| `mini` | Minimal setup with basic shell tools. Sets hostname to `mini-${serial_number}`. |
| `develop` | Extends mini with asdf version manager. Preserves existing hostname. |

## Bootstrap

Run on a fresh macOS machine:

```bash
# Mini profile
curl -fsSL https://raw.githubusercontent.com/vlj91/nix/main/bootstrap.sh | bash -s mini

# Develop profile
curl -fsSL https://raw.githubusercontent.com/vlj91/nix/main/bootstrap.sh | bash -s develop
```

## Auto-updates

Enable automatic updates (polls git remote hourly):

```bash
~/.config/nix-darwin/update.sh --install
```

Other commands:

```bash
./update.sh --check        # Check and apply updates now
./update.sh --status       # Show status
./update.sh --uninstall    # Disable auto-updates
```

## Manual rebuild

```bash
darwin-rebuild switch --flake ~/.config/nix-darwin#mini
# or
darwin-rebuild switch --flake ~/.config/nix-darwin#develop
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
