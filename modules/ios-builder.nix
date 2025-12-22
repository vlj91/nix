{ config, pkgs, lib, ... }:

let
  # Read username for activation script
  usernameFile =
    if builtins.pathExists /etc/nix-darwin/username.local
    then /etc/nix-darwin/username.local
    else ../username.local;
  username = if builtins.pathExists usernameFile
    then lib.strings.trim (builtins.readFile usernameFile)
    else "admin";

  # Read Orchard bootstrap token from local config file
  orchardTokenFile =
    if builtins.pathExists /etc/nix-darwin/orchard-token.local
    then /etc/nix-darwin/orchard-token.local
    else ../orchard-token.local;
  bootstrapToken = if builtins.pathExists orchardTokenFile
    then lib.strings.trim (builtins.readFile orchardTokenFile)
    else throw "Orchard bootstrap token not found. Please create ${orchardTokenFile}";

  # Read Orchard controller hostname from local config file
  orchardControllerFile =
    if builtins.pathExists /etc/nix-darwin/orchard-controller.local
    then /etc/nix-darwin/orchard-controller.local
    else ../orchard-controller.local;
  controllerHostname = if builtins.pathExists orchardControllerFile
    then lib.strings.trim (builtins.readFile orchardControllerFile)
    else throw "Orchard controller hostname not found. Please create ${orchardControllerFile}";

  # Wrapper script that ensures Tailscale is connected before starting orchard
  orchardWorkerWrapper = pkgs.writeShellScript "orchard-worker-wrapper" ''
    set -e

    # Maximum wait time: 5 minutes (300 seconds)
    MAX_WAIT=300
    ELAPSED=0
    RETRY_INTERVAL=5

    echo "[$(date)] Waiting for Tailscale to be connected..."

    while [ $ELAPSED -lt $MAX_WAIT ]; do
      if ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
        echo "[$(date)] Tailscale is connected, starting orchard worker..."
        exec ${pkgs.orchard}/bin/orchard worker run --user ${username} --bootstrap-token "${bootstrapToken}" "${controllerHostname}"
      fi

      echo "[$(date)] Tailscale not connected yet, waiting $RETRY_INTERVAL seconds... ($ELAPSED/$MAX_WAIT)"
      sleep $RETRY_INTERVAL
      ELAPSED=$((ELAPSED + RETRY_INTERVAL))
    done

    echo "[$(date)] ERROR: Tailscale did not connect within $MAX_WAIT seconds"
    exit 1
  '';
in
{
  # iOS builder profile does NOT modify hostname

  # Install tart for macOS virtualization and orchard for VM orchestration
  environment.systemPackages = [
    pkgs.tart
    pkgs.tailscale
    pkgs.orchard
  ];

  # Run Tailscale daemon
  launchd.daemons.tailscaled = {
    serviceConfig = {
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/var/log/tailscaled.out";
      StandardErrorPath = "/var/log/tailscaled.err";
      ProgramArguments = [
        "${pkgs.tailscale}/bin/tailscaled"
      ];
    };
  };

  # Run Orchard worker as launchd daemon (with Tailscale wrapper)
  launchd.daemons.orchard-worker = {
    # Path to required binaries
    path = [ pkgs.orchard pkgs.tailscale ];

    serviceConfig = {
      # Label for the service
      Label = "org.cirruslabs.orchard.worker";

      # Run on startup
      RunAtLoad = true;
      KeepAlive = true;

      # Working directory
      WorkingDirectory = "/var/empty";

      # Logging configuration
      StandardOutPath = "/Users/${username}/orchard-launchd.log";
      StandardErrorPath = "/Users/${username}/orchard-launchd.log";

      # Environment variables
      EnvironmentVariables = {
        PATH = "/bin:/usr/bin:/usr/local/bin:${pkgs.orchard}/bin:${pkgs.tailscale}/bin";
      };

      # Use wrapper script that waits for Tailscale
      ProgramArguments = [
        "${orchardWorkerWrapper}"
      ];
    };
  };

  # Initialize Tailscale on activation
  system.activationScripts.postActivation.text = ''
    echo "Configuring Tailscale..."
    # Authenticate Tailscale if auth key exists and not already connected
    if [ -f /etc/tailscale/keys/ephemeral ]; then
      # Wait briefly for tailscaled to be ready
      sleep 2
      if ! ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null | grep -q '"BackendState":"Running"'; then
        echo "Authenticating Tailscale with ephemeral key..."
        ${pkgs.tailscale}/bin/tailscale up --authkey="$(cat /etc/tailscale/keys/ephemeral)" --reset || true
      else
        echo "Tailscale already connected"
      fi
    else
      echo "Warning: Tailscale auth key not found at /etc/tailscale/keys/ephemeral"
    fi
  '';
}
