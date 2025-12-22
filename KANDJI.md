# Kandji Blueprint Setup Guide

This guide explains how to configure Kandji blueprints for automated deployment of nix-darwin configurations across different machine types.

## Overview

We use Kandji blueprints to automatically bootstrap macOS machines with nix-darwin configurations. Each machine type (mini, develop, ios-builder) gets its own blueprint with appropriate scripts and parameters.

## Prerequisites

- Access to Kandji admin console
- This repository uploaded to GitHub (or accessible git remote)
- Secrets ready for ios-builder machines (if applicable)

## Blueprint Architecture

Each blueprint contains:
1. **Bootstrap Script** - Main script that installs Nix and applies configuration
2. **Secret Parameters** - Secure storage for sensitive values (tokens, keys)
3. **Auto-Assignment Rules** - Automatically assign machines to blueprints

---

## Creating Custom Scripts

### 1. Bootstrap Script for All Profiles

**Script Name:** `nix-darwin-bootstrap`

**Description:** Bootstrap script that installs nix-darwin and applies configuration

**Execution Frequency:** Once per enrollment

**Run as:** Root

**Script Type:** Bash

**Script Content:** Upload `bootstrap-kandji.sh` from this repository

**Parameters:**
- Create a parameter called `PROFILE` (see profile-specific sections below)

---

## Blueprint 1: Mini Profile (Orchard Controllers)

### Purpose
Minimal Mac Mini machines that run Orchard controllers for orchestrating iOS CI/CD workers.

### Script Configuration

**Custom Script:** `nix-darwin-bootstrap`
- **Parameter `PROFILE`:** `mini`
- **Execution:** Once per enrollment
- **Failure Action:** Retry

### Parameters Required

None - hostname is auto-generated from serial number.

### Auto-Assignment Rules

Create an auto-assignment rule based on:
- **Model:** Mac Mini
- **Device Name Pattern:** `mini-*` (optional, helps identify these machines)

### Validation

After enrollment, verify:
```bash
# Check hostname is set to mini-${serial}
hostname

# Check orchard controller is running
sudo launchctl list | grep orchard-controller

# Check tailscale is running
tailscale status
```

---

## Blueprint 2: Develop Profile (Developer Machines)

### Purpose
Developer workstations with additional development tools (asdf, homebrew, etc).

### Script Configuration

**Custom Script:** `nix-darwin-bootstrap`
- **Parameter `PROFILE`:** `develop`
- **Execution:** Once per enrollment
- **Failure Action:** Retry

### Parameters Required

None - username is auto-detected, hostname is preserved.

### Auto-Assignment Rules

Create an auto-assignment rule based on:
- **Device Assignment:** Assign to specific users or groups
- **Device Name Pattern:** Developer machine naming pattern

### Validation

After enrollment, verify:
```bash
# Check asdf is installed
asdf --version

# Check homebrew is available
brew --version

# Check nix-darwin is active
darwin-rebuild --version
```

---

## Blueprint 3: iOS Builder Profile (CI/CD Workers)

### Purpose
iOS build machines that run as Orchard workers, connecting to Orchard controllers via Tailscale.

### Script Configuration

**Custom Script:** `nix-darwin-bootstrap`
- **Parameter `PROFILE`:** `ios-builder`
- **Execution:** Once per enrollment
- **Failure Action:** Retry

### Parameters Required

Create the following **Parameters** in Kandji (Parameters > Library Items > New Parameter):

#### 1. Orchard Bootstrap Token
- **Name:** `ORCHARD_BOOTSTRAP_TOKEN`
- **Type:** Text (Encrypted)
- **Description:** Bootstrap token for Orchard worker authentication
- **Value:** `orchard-bootstrap-token-v0.d29ya2VyLXBvb2wtbTQ...` (from Orchard controller)
- **Scope:** Add to ios-builder blueprint only

#### 2. Orchard Controller Hostname
- **Name:** `ORCHARD_CONTROLLER_HOSTNAME`
- **Type:** Text
- **Description:** Hostname of the Orchard controller (Tailscale hostname)
- **Value:** `mini-XXXXX.tailXXXXX.ts.net` (your controller's Tailscale hostname)
- **Scope:** Add to ios-builder blueprint only

#### 3. Tailscale Auth Key
- **Name:** `TAILSCALE_AUTH_KEY`
- **Type:** Text (Encrypted)
- **Description:** Ephemeral auth key for Tailscale authentication
- **Value:** `tskey-auth-XXXXX-XXXXX` (generate from Tailscale admin console)
- **Scope:** Add to ios-builder blueprint only
- **Note:** Use ephemeral keys with auto-expiry for better security

### Pre-Installation Script

Add a **Pre-Installation Script** that runs before the bootstrap script to set up secrets:

**Script Name:** `setup-ios-builder-secrets`

**Run as:** Root

**Execution:** Once per enrollment

**Script Content:**
```bash
#!/bin/bash
set -e

# Create directories
mkdir -p /etc/nix-darwin
mkdir -p /etc/tailscale/keys

# Write Orchard secrets (these will be injected by Kandji)
echo "$ORCHARD_BOOTSTRAP_TOKEN" > /etc/nix-darwin/orchard-token.local
chmod 600 /etc/nix-darwin/orchard-token.local

echo "$ORCHARD_CONTROLLER_HOSTNAME" > /etc/nix-darwin/orchard-controller.local
chmod 600 /etc/nix-darwin/orchard-controller.local

# Write Tailscale auth key
echo "$TAILSCALE_AUTH_KEY" > /etc/tailscale/keys/ephemeral
chmod 600 /etc/tailscale/keys/ephemeral

echo "iOS builder secrets configured successfully"
```

### Script Execution Order

1. **setup-ios-builder-secrets** (runs first)
2. **nix-darwin-bootstrap** (runs second with PROFILE=ios-builder)

### Auto-Assignment Rules

Create an auto-assignment rule based on:
- **Model:** Mac Mini or specific hardware model
- **Device Name Pattern:** `ios-builder-*` or your naming convention
- **Device Group:** iOS CI/CD Workers group

### Validation

After enrollment, verify:
```bash
# Check secrets exist
sudo ls -la /etc/nix-darwin/orchard-*
sudo ls -la /etc/tailscale/keys/ephemeral

# Check tailscale is connected
tailscale status

# Check orchard worker is running and connected
sudo launchctl list | grep orchard-worker
tail -f /Users/admin/orchard-launchd.log

# Check tart is installed
tart --version
```

---

## Step-by-Step Kandji Setup

### 1. Upload Bootstrap Script

1. Navigate to **Library > Custom Scripts**
2. Click **+ Add Script**
3. Configure:
   - **Name:** `nix-darwin-bootstrap`
   - **Execution Frequency:** Once per enrollment
   - **Script Content:** Upload `bootstrap-kandji.sh`
   - **Run as:** Root
4. Click **Save**

### 2. Create Parameters (iOS Builder Only)

1. Navigate to **Library > Parameters**
2. Click **+ Add Parameter**
3. Create each parameter listed in the iOS Builder section above
4. Mark sensitive parameters as "Encrypted"

### 3. Create Pre-Installation Script (iOS Builder Only)

1. Navigate to **Library > Custom Scripts**
2. Click **+ Add Script**
3. Configure:
   - **Name:** `setup-ios-builder-secrets`
   - **Execution Frequency:** Once per enrollment
   - **Script Content:** Copy the pre-installation script from above
   - **Run as:** Root
4. Add parameter mappings in script variables section:
   - `$ORCHARD_BOOTSTRAP_TOKEN` → Parameter: `ORCHARD_BOOTSTRAP_TOKEN`
   - `$ORCHARD_CONTROLLER_HOSTNAME` → Parameter: `ORCHARD_CONTROLLER_HOSTNAME`
   - `$TAILSCALE_AUTH_KEY` → Parameter: `TAILSCALE_AUTH_KEY`
5. Click **Save**

### 4. Create Blueprints

For each profile (mini, develop, ios-builder):

1. Navigate to **Blueprints**
2. Click **+ Add Blueprint**
3. Configure:
   - **Name:** `[Profile Name] - nix-darwin` (e.g., "Mini - nix-darwin")
   - **Description:** Describe the purpose
4. Add Library Items:
   - **Scripts Tab:** Add `nix-darwin-bootstrap`
     - Set parameter `PROFILE` to appropriate value (`mini`, `develop`, or `ios-builder`)
   - **For iOS Builder:** Also add `setup-ios-builder-secrets` (ensure it runs before bootstrap)
   - **Parameters Tab (iOS Builder only):** Add all three parameters
5. Configure auto-assignment rules (optional)
6. Click **Save**

### 5. Test the Blueprint

1. Enroll a test machine using the blueprint
2. Monitor **Devices > [Device] > Activity** for script execution
3. Check logs in Kandji for any errors
4. SSH into the machine and run validation commands

---

## Troubleshooting

### Script Fails During Execution

**Check Kandji Activity Log:**
1. Go to **Devices > [Device] > Activity**
2. Find the failed script execution
3. Review stdout/stderr output

**Common Issues:**
- **"Nix command not found":** Nix installation failed - check network connectivity
- **"Could not determine user":** No user logged in (wait for console user)
- **"Orchard token not found" (iOS Builder):** Pre-installation script didn't run or failed

### Orchard Worker Not Connecting (iOS Builder)

**Check logs:**
```bash
# Orchard worker logs
tail -f /Users/admin/orchard-launchd.log

# Tailscale logs
tail -f /var/log/tailscaled.out
```

**Common Issues:**
- **"Waiting for Tailscale to be connected":** Tailscale auth key invalid or expired
- **"ERROR: Tailscale did not connect within 300 seconds":** Network issue or invalid auth key
- **Connection refused to controller:** Controller hostname incorrect or controller not running

### Secrets Not Being Written (iOS Builder)

**Verify parameters are assigned:**
1. Go to **Blueprints > [iOS Builder Blueprint] > Parameters**
2. Ensure all three parameters are added and have values
3. Check parameter mappings in the pre-installation script

**Verify script variable substitution:**
1. Go to **Library > Custom Scripts > setup-ios-builder-secrets**
2. Check that script variables are properly mapped to parameters

---

## Security Best Practices

### Tailscale Auth Keys
- Use **ephemeral keys** that auto-expire
- Set **key expiry** to 90 days maximum
- Use **reusable keys** for multiple machines of same type
- Generate keys with minimal permissions

### Orchard Tokens
- Use **separate tokens** for different worker pools
- Rotate tokens periodically
- Revoke tokens for decommissioned machines

### Parameter Encryption
- Mark all sensitive parameters as **Encrypted** in Kandji
- Never log parameter values in scripts
- Use `chmod 600` on all secret files

### Secret Files
- Store in `/etc/nix-darwin/` (system directory, requires root)
- Use `/etc/tailscale/keys/` for Tailscale secrets
- Never commit `.local` files to git (already in `.gitignore`)

---

## Updating Configurations

### Update nix-darwin Configuration

Changes to this repository are automatically applied via the auto-update daemon:
1. Push changes to the git repository
2. Wait up to 1 hour for auto-update to run (or trigger manually)
3. Configuration will rebuild automatically

### Update Kandji Scripts

When updating bootstrap scripts:
1. Update `bootstrap-kandji.sh` in this repository
2. Update the script in **Library > Custom Scripts** in Kandji
3. Machines will use new script on next enrollment

### Rotate Secrets (iOS Builder)

To rotate secrets without re-enrollment:
1. Update parameter values in Kandji
2. Re-run the `setup-ios-builder-secrets` script manually:
   - **Devices > [Device] > Actions > Run Custom Script**
3. Rebuild nix-darwin configuration:
   ```bash
   sudo darwin-rebuild switch --flake /etc/nix-darwin#ios-builder --impure
   ```

---

## Reference: Blueprint Matrix

| Blueprint | Profile | Scripts | Parameters | Auto-Assignment |
|-----------|---------|---------|------------|-----------------|
| **Mini - nix-darwin** | `mini` | bootstrap-kandji.sh | None | Mac Mini models |
| **Develop - nix-darwin** | `develop` | bootstrap-kandji.sh | None | Developer group |
| **iOS Builder - nix-darwin** | `ios-builder` | 1. setup-ios-builder-secrets<br>2. bootstrap-kandji.sh | 1. ORCHARD_BOOTSTRAP_TOKEN<br>2. ORCHARD_CONTROLLER_HOSTNAME<br>3. TAILSCALE_AUTH_KEY | iOS CI/CD group |

---

## Getting Secrets

### Orchard Bootstrap Token
1. SSH into your Orchard controller (Mini machine)
2. Generate a worker bootstrap token:
   ```bash
   orchard create-bootstrap-token --pool <pool-name>
   ```
3. Copy the token (starts with `orchard-bootstrap-token-v0`)

### Orchard Controller Hostname
1. On the controller machine, get Tailscale hostname:
   ```bash
   tailscale status | grep $(hostname) | awk '{print $2}'
   ```
2. Use this hostname (e.g., `mini-XXXXX.tailXXXXX.ts.net`)

### Tailscale Auth Key
1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys)
2. Click **Generate auth key**
3. Configure:
   - **Reusable:** Yes (for multiple workers)
   - **Ephemeral:** Yes (recommended)
   - **Expires:** 90 days
   - **Tags:** `tag:orchard-worker` (optional)
4. Copy the key (starts with `tskey-auth-`)
