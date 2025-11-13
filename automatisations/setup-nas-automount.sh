#!/usr/bin/env bash

# ============================================================================
# NAS Auto-Mount Setup
# Configures automatic mounting of SMB/NAS shares at startup
#
# SECURITY NOTICE:
# - Passwords are stored ONLY in macOS Keychain (AES-256-GCM encryption)
# - Passwords are NEVER written to TOML files, logs, or temporary files
# - Automatic mounting uses AppleScript which securely handles credentials
# - Initial share discovery uses smbutil which briefly exposes password in
#   process arguments (~2-10 seconds). This is a one-time setup operation.
# - For maximum security on multi-user systems, manually configure shares in
#   mac-setup.toml to avoid interactive discovery.
# ============================================================================

set -euo pipefail
set +o history  # Disable shell history to prevent password leakage

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
  source "$PROJECT_ROOT/lib/toml-parser.sh"
fi

# ============================================================================
# Configuration
# ============================================================================
LAUNCHAGENT_LABEL="com.user.nas-automount"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
KEYCHAIN_SERVICE_PREFIX="nas-share"
DEFAULT_MOUNT_BASE="/Volumes"
DEFAULT_WAIT_TIMEOUT=60

# ============================================================================
# Helper Functions
# ============================================================================

# Wait for network connectivity to server
wait_for_network() {
  local server="$1"
  local timeout="${2:-60}"
  local interval=2
  local elapsed=0

  log_info "Attente de la connectivité réseau vers $server..."

  # Remove smb:// prefix if present
  server="${server#smb://}"
  server="${server#//}"

  while ! ping -c 1 -W 2 "$server" &>/dev/null; do
    sleep $interval
    elapsed=$((elapsed + interval))

    if [[ $elapsed -ge $timeout ]]; then
      log_error "Timeout réseau après ${elapsed}s"
      return 1
    fi

    if [[ $((elapsed % 10)) -eq 0 ]]; then
      log_verbose "Attente réseau... ${elapsed}s"
    fi
  done

  log_success "Réseau disponible"
  return 0
}

# Check if share is already mounted
is_share_mounted() {
  local mountpoint="$1"
  mount | grep -q " on ${mountpoint} "
}

# Get password from macOS Keychain
get_keychain_password() {
  local service="$1"
  local username="$2"

  security find-generic-password -w -a "$username" -s "$service" 2>/dev/null || echo ""
}

# Store password in macOS Keychain
store_keychain_password() {
  local service="$1"
  local username="$2"
  local password="$3"

  # Delete existing entry if present (to update)
  security delete-generic-password -a "$username" -s "$service" 2>/dev/null || true

  # Add new entry
  security add-generic-password \
    -a "$username" \
    -s "$service" \
    -l "SMB mount for $service" \
    -w "$password" \
    -U 2>/dev/null
}

# URL-encode string for SMB URL (handles special characters in passwords)
url_encode() {
  local string="$1"

  # Use perl for URL encoding (available on macOS by default)
  if command_exists perl; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$string"
  else
    # Fallback: simple encoding for common characters
    echo "$string" | sed \
      -e 's/ /%20/g' \
      -e 's/!/%21/g' \
      -e 's/"/%22/g' \
      -e 's/#/%23/g' \
      -e 's/\$/%24/g' \
      -e 's/&/%26/g' \
      -e "s/'/%27/g" \
      -e 's/(/%28/g' \
      -e 's/)/%29/g' \
      -e 's/\*/%2A/g' \
      -e 's/+/%2B/g' \
      -e 's/,/%2C/g' \
      -e 's/@/%40/g'
  fi
}

# List available shares on SMB server
list_smb_shares() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_step "Découverte des partages disponibles sur $server..." >&2

  # Remove smb:// prefix if present
  server="${server#smb://}"
  server="${server#//}"

  # Step 1: Verify server is reachable
  log_verbose "Vérification de la connectivité au serveur..." >&2
  if ! ping -c 1 -W 2 "$server" &>/dev/null; then
    log_error "Serveur inaccessible: $server" >&2
    log_info "Vérifiez que le serveur est allumé et accessible sur le réseau" >&2
    return 1
  fi
  log_verbose "Serveur accessible" >&2

  # Step 2: Verify credentials and list shares
  local shares
  local smbutil_output
  local smbutil_exit_code
  local encoded_password

  # SECURITY NOTE: smbutil does not support stdin for passwords on macOS
  # The password will be briefly visible (2-10 seconds) in process arguments during discovery
  # This is a one-time operation during initial setup only. Regular mounts use secure AppleScript.
  # If this is a concern, manually edit mac-setup.toml shares list instead of interactive discovery.

  if [[ -n "$password" ]]; then
    # URL-encode password to handle special characters
    encoded_password=$(url_encode "$password")

    # With authentication (no -A flag: authenticate AND list shares)
    # WARNING: Password briefly visible in ps aux during this command (~2-10 sec exposure)
    smbutil_output=$(smbutil view "//${username}:${encoded_password}@${server}" 2>&1)
    smbutil_exit_code=$?
  else
    # Try without authentication (guest)
    smbutil_output=$(smbutil view "//${server}" 2>&1)
    smbutil_exit_code=$?
  fi

  # Step 3: Check for authentication errors
  if [[ $smbutil_exit_code -ne 0 ]]; then
    if echo "$smbutil_output" | grep -qi "authentication\|credentials\|password"; then
      log_error "Échec d'authentification sur $server" >&2
      log_info "Vérifiez que le nom d'utilisateur et le mot de passe sont corrects" >&2
    else
      log_error "Impossible de se connecter au serveur SMB: $server" >&2
      log_verbose "Erreur smbutil: $smbutil_output" >&2
      log_info "Vérifiez que le service SMB est actif sur le serveur" >&2
    fi
    return 1
  fi

  # Step 4: Extract share names
  shares=$(echo "$smbutil_output" | grep "Disk" | awk '{print $1}' | grep -v "^$")

  if [[ -z "$shares" ]]; then
    log_error "Aucun partage disponible sur $server" >&2
    log_info "Le serveur ne partage aucun volume ou vous n'avez pas les permissions" >&2
    return 1
  fi

  echo "$shares"
  return 0
}

# Interactive share selection with fzf
select_shares_interactive() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_subsection "Sélection interactive des partages" >&2

  # Check if fzf is available
  if ! command_exists fzf; then
    log_error "fzf n'est pas installé (requis pour la sélection interactive)" >&2
    log_info "fzf devrait être installé via le module brew-packages" >&2
    return 1
  fi

  # List available shares (with proper error handling)
  local available_shares
  if ! available_shares=$(list_smb_shares "$server" "$username" "$password" 2>&2); then
    # list_smb_shares already logged the error
    log_error "Impossible de continuer sans partages disponibles" >&2
    return 1
  fi

  # Double-check that we actually got shares (defense in depth)
  if [[ -z "$available_shares" ]]; then
    log_error "Aucun partage retourné (erreur interne)" >&2
    return 1
  fi

  local share_count
  share_count=$(echo "$available_shares" | wc -l | xargs)
  log_success "$share_count partages découverts" >&2

  # Display shares in console (before fzf)
  echo "" >&2
  log_info "Partages disponibles sur $server :" >&2
  echo "$available_shares" | sed 's/^/  - /' >&2
  echo "" >&2

  # Display shares and use fzf for multi-selection (only share names, no logs)
  local selected
  selected=$(echo "$available_shares" | fzf \
    --multi \
    --height=60% \
    --border \
    --prompt="Sélectionnez les partages à monter automatiquement (TAB pour sélectionner, ENTER pour confirmer): " \
    --header="$share_count partages disponibles sur $server" \
    --preview="echo 'Sera monté dans: /Volumes/{}'" \
    --preview-window=down:3:wrap)

  if [[ -z "$selected" ]]; then
    log_warning "Aucun partage sélectionné" >&2
    return 1
  fi

  local selected_count
  selected_count=$(echo "$selected" | wc -l | xargs)
  log_success "$selected_count partages sélectionnés" >&2

  echo "$selected"
  return 0
}

# Mount a single SMB share
mount_smb_share() {
  local share_name="$1"
  local server="$2"
  local display_name="$3"
  local username="$4"
  local password="$5"
  local mount_base="$6"

  local mountpoint="${mount_base}/${share_name}"

  log_step "Montage: $share_name"

  # Check if already mounted
  if is_share_mounted "$mountpoint"; then
    log_success "Déjà monté: $mountpoint"
    return 0
  fi

  # Remove smb:// prefix if present from both server and display_name
  server="${server#smb://}"
  server="${server#//}"
  display_name="${display_name#smb://}"
  display_name="${display_name#//}"

  # Determine which address to use for mounting
  # Try to use display_name if it's resolvable, otherwise fall back to server IP
  local mount_address="$server"
  if [[ -n "$display_name" ]] && [[ "$display_name" != "$server" ]]; then
    # Try to resolve display_name
    if ping -c 1 -W 2 "$display_name" &>/dev/null; then
      mount_address="$display_name"
      log_verbose "Utilisation du nom d'affichage: $display_name"
    else
      log_verbose "Le nom d'affichage '$display_name' ne résout pas, utilisation de l'IP: $server"
    fi
  fi

  # Mount the share
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would mount: smb://${mount_address}/${share_name} to $mountpoint"
    return 0
  fi

  # SECURITY: Use osascript (AppleScript) to mount volume
  # This prevents password from appearing in process arguments visible via 'ps aux'
  # AppleScript's 'mount volume' command handles credentials securely
  # NOTE: AppleScript automatically creates the mount point in /Volumes/ with proper permissions
  # Manual mkdir is not needed and would fail (macOS Sierra+ requires root for /Volumes/)
  # NOTE: The hostname/display_name used in the mount URL determines what Finder displays
  local mount_result
  mount_result=$(osascript 2>&1 <<EOF
tell application "Finder"
  try
    mount volume "smb://${mount_address}/${share_name}" as user name "${username}" with password "${password}"
    return "success"
  on error errMsg
    return "error:" & errMsg
  end try
end tell
EOF
)

  if [[ "$mount_result" == "success" ]]; then
    log_success "Monté: $share_name → $mountpoint"
    return 0
  else
    # If osascript fails, log error
    log_error "Échec du montage: $share_name"
    if [[ "$mount_result" =~ ^error: ]]; then
      local error_msg="${mount_result#error:}"
      log_verbose "Erreur AppleScript: $error_msg"
    fi
    log_info "Vérifiez les credentials et la connectivité réseau"
    return 1
  fi
}

# Create LaunchAgent plist file
create_launchagent() {
  local script_path="$1"

  log_step "Création du LaunchAgent..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create: $LAUNCHAGENT_PLIST"
    return 0
  fi

  # Ensure LaunchAgents directory exists
  mkdir -p "$HOME/Library/LaunchAgents"

  # Create plist file
  cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHAGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${script_path}</string>
    <string>--mount-only</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>

  <key>ThrottleInterval</key>
  <integer>60</integer>

  <key>StandardOutPath</key>
  <string>/tmp/nas-automount.log</string>

  <key>StandardErrorPath</key>
  <string>/tmp/nas-automount-error.log</string>

  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
  </dict>
</dict>
</plist>
EOF

  if [[ $? -eq 0 ]]; then
    log_success "LaunchAgent créé: $LAUNCHAGENT_PLIST"
    return 0
  else
    log_error "Échec de la création du LaunchAgent"
    return 1
  fi
}

# Install and load LaunchAgent
install_launchagent() {
  log_step "Installation du LaunchAgent..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: launchctl load $LAUNCHAGENT_PLIST"
    return 0
  fi

  # Unload if already loaded
  if launchctl list | grep -q "$LAUNCHAGENT_LABEL"; then
    log_verbose "Déchargement de l'ancien LaunchAgent..."
    launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true
  fi

  # Load new LaunchAgent
  if launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null; then
    log_success "LaunchAgent installé et activé"
    log_info "Les partages seront montés automatiquement au prochain login"
    return 0
  else
    log_error "Échec du chargement du LaunchAgent"
    return 1
  fi
}

# Update TOML configuration with NAS settings
update_toml_config() {
  local server="$1"
  local display_name="$2"
  local username="$3"
  local shares="$4"
  local mount_base="$5"

  log_step "Mise à jour de la configuration TOML..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would update $TOML_CONFIG with NAS configuration"
    return 0
  fi

  # Check if [automations.nas-shares] section exists
  if grep -q "\[automations.nas-shares\]" "$TOML_CONFIG" 2>/dev/null; then
    log_warning "Section [automations.nas-shares] existe déjà dans $TOML_CONFIG"
    log_info "Mise à jour manuelle requise ou supprimez la section existante"
    return 0
  fi

  # Convert shares to TOML array format
  local shares_array="["
  local first=true
  while IFS= read -r share; do
    if [[ "$first" == "true" ]]; then
      shares_array+="\"$share\""
      first=false
    else
      shares_array+=", \"$share\""
    fi
  done <<< "$shares"
  shares_array+="]"

  # Append NAS configuration to TOML file
  cat >> "$TOML_CONFIG" << EOF

# -----------------------------------------------------------------------------
# NAS Auto-Mount Configuration
# -----------------------------------------------------------------------------
[automations.nas-shares]
enabled = true
server = "$server"
display_name = "$display_name"
username = "$username"
mount_base = "$mount_base"
wait_timeout = $DEFAULT_WAIT_TIMEOUT

# Partages sélectionnés (modifiable)
shares = $shares_array
EOF

  if [[ $? -eq 0 ]]; then
    log_success "Configuration TOML mise à jour"
    return 0
  else
    log_error "Échec de la mise à jour de la configuration TOML"
    return 1
  fi
}

# Read NAS configuration from TOML
read_nas_config() {
  local config_server config_display_name config_username config_mount_base config_wait_timeout

  config_server=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.server" 2>/dev/null || echo "")
  config_display_name=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.display_name" 2>/dev/null || echo "")
  config_username=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.username" 2>/dev/null || echo "")
  config_mount_base=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.mount_base" 2>/dev/null || echo "$DEFAULT_MOUNT_BASE")
  config_wait_timeout=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.wait_timeout" 2>/dev/null || echo "$DEFAULT_WAIT_TIMEOUT")

  # Strip surrounding quotes from values (dasel returns values with quotes)
  # Strip both double quotes (") and single quotes (')
  config_server="${config_server//\"/}"
  config_server="${config_server//\'/}"
  config_display_name="${config_display_name//\"/}"
  config_display_name="${config_display_name//\'/}"
  config_username="${config_username//\"/}"
  config_username="${config_username//\'/}"
  config_mount_base="${config_mount_base//\"/}"
  config_mount_base="${config_mount_base//\'/}"
  config_wait_timeout="${config_wait_timeout//\"/}"
  config_wait_timeout="${config_wait_timeout//\'/}"

  # If display_name is empty, use server as fallback
  if [[ -z "$config_display_name" ]]; then
    config_display_name="$config_server"
  fi

  echo "$config_server|$config_display_name|$config_username|$config_mount_base|$config_wait_timeout"
}

# Read shares list from TOML
read_shares_from_toml() {
  parse_toml_array "$TOML_CONFIG" "automations.nas-shares.shares" 2>/dev/null || echo ""
}

# Convert display name to valid DNS hostname
sanitize_hostname() {
  local display_name="$1"
  local hostname

  # Convert to lowercase and replace spaces/underscores with hyphens
  hostname=$(echo "$display_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--')

  # Remove any characters that aren't alphanumeric, hyphens, or dots
  hostname=$(echo "$hostname" | sed 's/[^a-z0-9.-]//g')

  # Add .local suffix if not present
  if [[ ! "$hostname" =~ \.local$ ]]; then
    hostname="${hostname}.local"
  fi

  echo "$hostname"
}

# Update /etc/hosts with NAS hostname mapping
update_etc_hosts() {
  local server_ip="$1"
  local hostname="$2"

  log_step "Mise à jour de /etc/hosts..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would add to /etc/hosts: $server_ip  $hostname"
    return 0
  fi

  # Check if entry already exists
  if grep -q "$hostname" /etc/hosts 2>/dev/null; then
    # Check if IP matches
    if grep -q "^${server_ip}[[:space:]].*${hostname}" /etc/hosts; then
      log_success "Entrée déjà présente dans /etc/hosts"
      return 0
    else
      log_warning "Hostname '$hostname' existe déjà avec une IP différente"
      log_info "Mise à jour de l'entrée..."

      # Remove old entry and add new one (requires sudo)
      if sudo sed -i '' "/${hostname}/d" /etc/hosts && \
         echo "$server_ip  $hostname  # Added by mac-setup NAS automation" | sudo tee -a /etc/hosts >/dev/null; then
        log_success "Entrée mise à jour dans /etc/hosts"
        return 0
      else
        log_error "Échec de la mise à jour de /etc/hosts"
        return 1
      fi
    fi
  else
    # Add new entry (requires sudo)
    log_info "Ajout de l'entrée à /etc/hosts (sudo requis)..."

    if echo "$server_ip  $hostname  # Added by mac-setup NAS automation" | sudo tee -a /etc/hosts >/dev/null; then
      log_success "Entrée ajoutée à /etc/hosts: $server_ip → $hostname"
      log_info "Le serveur sera accessible via '$hostname'"
      return 0
    else
      log_error "Échec de l'ajout à /etc/hosts"
      log_info "Vous pouvez ajouter manuellement: $server_ip  $hostname"
      return 1
    fi
  fi
}

# Validate existing configuration
validate_existing_config() {
  local server="$1"
  local username="$2"
  local issues=()
  local is_valid=true

  log_verbose "Validation de la configuration existante..."

  # Check 1: Keychain password exists
  local keychain_service="${KEYCHAIN_SERVICE_PREFIX}-${server}"
  local password
  password=$(get_keychain_password "$keychain_service" "$username")

  if [[ -z "$password" ]]; then
    issues+=("⚠️  Mot de passe non trouvé dans le Keychain")
    is_valid=false
  else
    log_verbose "✓ Identifiants trouvés dans le Keychain"
  fi

  # Check 2: LaunchAgent plist exists
  if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
    issues+=("⚠️  LaunchAgent manquant")
    # Not critical - can be recreated
    log_verbose "⚠ LaunchAgent manquant (peut être recréé)"
  else
    log_verbose "✓ LaunchAgent installé"
  fi

  # Check 3: Shares list exists
  local shares
  shares=$(read_shares_from_toml)
  if [[ -z "$shares" ]]; then
    issues+=("⚠️  Aucun partage configuré")
    is_valid=false
  else
    local share_count
    share_count=$(echo "$shares" | wc -l | xargs)
    log_verbose "✓ $share_count partages configurés"
  fi

  # Optional Check 4: Server network connectivity (non-blocking warning)
  local server_clean="${server#smb://}"
  server_clean="${server_clean#//}"
  if ! ping -c 1 -W 2 "$server_clean" &>/dev/null; then
    issues+=("⚠️  Serveur inaccessible (peut être temporairement hors ligne)")
    log_verbose "⚠ Serveur inaccessible (non bloquant)"
  else
    log_verbose "✓ Serveur accessible sur le réseau"
  fi

  # Return validation result
  if [[ "$is_valid" == "false" ]]; then
    # Print issues to stderr for caller to display
    for issue in "${issues[@]}"; do
      echo "$issue" >&2
    done
    return 1
  fi

  return 0
}

# Show configuration choice menu with fzf
show_config_choice_menu() {
  local server="$1"
  local username="$2"

  # Check if fzf is available
  if ! command_exists fzf; then
    log_error "fzf n'est pas installé (requis pour le menu interactif)" >&2
    log_info "Utilisation de la configuration existante par défaut" >&2
    echo "1"
    return 0
  fi

  # Show configuration info
  echo "" >&2
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  log_info "  Configuration NAS détectée" >&2
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  echo "" >&2
  log_success "Serveur:     $server" >&2
  log_success "Utilisateur: $username" >&2

  # Show shares count
  local shares
  shares=$(read_shares_from_toml)
  if [[ -n "$shares" ]]; then
    local share_count
    share_count=$(echo "$shares" | wc -l | xargs)
    log_success "Partages:    $share_count configurés" >&2
  fi

  # Show validation status
  echo "" >&2
  local validation_output
  if validation_output=$(validate_existing_config "$server" "$username" 2>&1); then
    log_success "✓ Configuration complète et valide" >&2
  else
    log_warning "⚠ Configuration incomplète" >&2
  fi
  echo "" >&2

  # Prepare options for fzf (format: "ID|Title|Description")
  local options=(
    "1|Réutiliser la configuration existante|Monte les partages avec la config actuelle"
    "2|Reconfigurer complètement|Redemande serveur, credentials et partages"
    "3|Annuler|Ignore la configuration NAS pour cette session"
  )

  # Use fzf to select option
  local selected
  selected=$(printf '%s\n' "${options[@]}" | fzf \
    --height=50% \
    --border=rounded \
    --prompt="Que voulez-vous faire ? " \
    --header="Configuration NAS existante" \
    --delimiter="|" \
    --with-nth=2 \
    --preview='echo {3}' \
    --preview-window=down:3:wrap | cut -d'|' -f1)

  # Return selected choice (or default to 1 if cancelled)
  if [[ -z "$selected" ]]; then
    log_warning "Aucun choix sélectionné, utilisation de la config existante" >&2
    echo "1"
  else
    echo "$selected"
  fi
}

# Reuse existing configuration
reuse_existing_config() {
  local server="$1"
  local username="$2"

  log_subsection "Réutilisation de la configuration existante"

  # Ensure LaunchAgent is installed (recreate if missing)
  if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
    log_warning "LaunchAgent manquant, recréation..."
    local script_path="$SCRIPT_DIR/$(basename "$0")"
    create_launchagent "$script_path"
    install_launchagent
  else
    log_success "LaunchAgent déjà installé"
  fi

  # Optionally test mount (if not dry-run)
  if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    read -r -p "Voulez-vous tester le montage des partages maintenant ? (O/n): " test_mount

    # Default to "yes" if empty or explicitly "o/O/y/Y"
    if [[ -z "$test_mount" ]] || [[ "$test_mount" =~ ^[oOyY]$ ]]; then
      echo ""
      mount_nas_shares
    else
      log_info "Les partages seront montés automatiquement au prochain login"
    fi
  fi

  log_success "Configuration réutilisée avec succès"
  return 0
}

# ============================================================================
# Main Functions
# ============================================================================

# Interactive setup (first-time configuration or reconfiguration)
# This function performs the actual setup WITHOUT checking for existing config
# Parameters (optional): existing_server, existing_username (for pre-filling during reconfigure)
do_interactive_setup() {
  local existing_server="${1:-}"
  local existing_username="${2:-}"

  log_subsection "Configuration interactive du montage NAS"

  # Step 1: Get NAS server (with optional default)
  log_step "Configuration du serveur NAS"

  echo ""
  local nas_server
  if [[ -n "$existing_server" ]]; then
    read -r -p "Entrez l'adresse du serveur NAS [$existing_server]: " nas_server
    nas_server="${nas_server:-$existing_server}"  # Use existing if empty
  else
    read -r -p "Entrez l'adresse du serveur NAS (ex: Ours-Imposant, nas.local, 192.168.1.100): " nas_server
  fi

  if [[ -z "$nas_server" ]]; then
    log_error "Serveur NAS requis"
    return 1
  fi

  # Remove smb:// prefix if user entered it
  nas_server="${nas_server#smb://}"
  nas_server="${nas_server#//}"

  log_success "Serveur NAS: $nas_server"

  # Step 1.5: Get display name (friendly name for Finder)
  echo ""
  local nas_display_name
  read -r -p "Nom d'affichage pour le Finder [Server NAS]: " nas_display_name
  nas_display_name="${nas_display_name:-Server NAS}"  # Default to "Server NAS"

  log_success "Nom d'affichage: $nas_display_name"

  # Step 1.6: Offer to add /etc/hosts entry for hostname resolution
  echo ""
  local suggested_hostname
  suggested_hostname=$(sanitize_hostname "$nas_display_name")

  log_info "Hostname suggéré: $suggested_hostname"
  log_info "Cela permettra au Finder d'afficher '$suggested_hostname' au lieu de l'IP"
  echo ""

  local add_to_hosts
  read -r -p "Voulez-vous ajouter une entrée DNS locale dans /etc/hosts ? (O/n): " add_to_hosts

  # Default to "yes" if empty or explicitly "o/O/y/Y"
  if [[ -z "$add_to_hosts" ]] || [[ "$add_to_hosts" =~ ^[oOyY]$ ]]; then
    echo ""
    log_warning "Cette opération nécessite les privilèges sudo (mot de passe administrateur)"
    echo ""

    if update_etc_hosts "$nas_server" "$suggested_hostname"; then
      # Update display_name to use the hostname instead
      nas_display_name="$suggested_hostname"
      log_success "Le serveur apparaîtra comme '$nas_display_name' dans le Finder"
    else
      log_warning "L'entrée /etc/hosts n'a pas pu être ajoutée"
      log_info "Le serveur apparaîtra comme '$nas_server' dans le Finder"
    fi
  else
    log_info "L'entrée /etc/hosts ne sera pas ajoutée"
    log_info "Le serveur apparaîtra comme '$nas_server' dans le Finder"
  fi

  # Step 2: Get credentials (with optional default for username)
  log_step "Configuration des identifiants"

  echo ""
  local nas_username
  if [[ -n "$existing_username" ]]; then
    read -r -p "Nom d'utilisateur NAS [$existing_username]: " nas_username
    nas_username="${nas_username:-$existing_username}"  # Use existing if empty
  else
    read -r -p "Nom d'utilisateur NAS: " nas_username
  fi

  if [[ -z "$nas_username" ]]; then
    log_error "Nom d'utilisateur requis"
    return 1
  fi

  # Password: always ask for security (never pre-fill)
  local nas_password
  read -r -s -p "Mot de passe NAS: " nas_password
  echo ""

  if [[ -z "$nas_password" ]]; then
    log_error "Mot de passe requis"
    return 1
  fi

  log_success "Identifiants configurés"

  # Step 3: Select shares interactively
  local selected_shares
  selected_shares=$(select_shares_interactive "$nas_server" "$nas_username" "$nas_password")

  if [[ -z "$selected_shares" ]]; then
    log_error "Aucun partage sélectionné"
    return 1
  fi

  # Step 4: Store credentials in Keychain
  log_step "Stockage des identifiants dans le Keychain..."

  local keychain_service="${KEYCHAIN_SERVICE_PREFIX}-${nas_server}"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would store credentials in Keychain: $keychain_service"
  else
    store_keychain_password "$keychain_service" "$nas_username" "$nas_password"
    log_success "Identifiants stockés dans le Keychain"
  fi

  # Step 5: Update TOML configuration
  update_toml_config "$nas_server" "$nas_display_name" "$nas_username" "$selected_shares" "$DEFAULT_MOUNT_BASE"

  # Step 6: Create and install LaunchAgent
  local script_path="$SCRIPT_DIR/$(basename "$0")"
  create_launchagent "$script_path"
  install_launchagent

  # Step 7: Offer to test mount now
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  Configuration terminée !"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -r -p "Voulez-vous monter les partages maintenant ? (O/n): " test_mount

    # Default to "yes" if empty or explicitly "o/O/y/Y"
    if [[ -z "$test_mount" ]] || [[ "$test_mount" =~ ^[oOyY]$ ]]; then
      echo ""
      mount_nas_shares
    else
      log_info "Les partages seront montés automatiquement au prochain login"
    fi
  fi

  return 0
}

# Mount all configured NAS shares
mount_nas_shares() {
  log_subsection "Montage des partages NAS"

  # Read configuration
  local config
  config=$(read_nas_config)

  IFS='|' read -r server display_name username mount_base wait_timeout <<< "$config"

  if [[ -z "$server" ]] || [[ -z "$username" ]]; then
    log_error "Configuration NAS non trouvée dans $TOML_CONFIG"
    log_info "Exécutez d'abord la configuration interactive"
    return 1
  fi

  log_info "Serveur: $display_name"
  log_info "Utilisateur: $username"
  log_info "Point de montage: $mount_base"

  # Read shares list
  local shares
  shares=$(read_shares_from_toml)

  if [[ -z "$shares" ]]; then
    log_error "Aucun partage configuré"
    return 1
  fi

  local share_count
  share_count=$(echo "$shares" | wc -l | xargs)
  log_info "Partages à monter: $share_count"

  # Wait for network
  if ! wait_for_network "$server" "$wait_timeout"; then
    log_error "Impossible de joindre le serveur NAS"
    return 1
  fi

  # Get password from Keychain
  local keychain_service="${KEYCHAIN_SERVICE_PREFIX}-${server}"
  local password
  password=$(get_keychain_password "$keychain_service" "$username")

  if [[ -z "$password" ]]; then
    log_error "Mot de passe non trouvé dans le Keychain: $keychain_service"
    log_info "Réexécutez la configuration interactive"
    return 1
  fi

  # Mount each share
  local mounted_count=0
  local failed_count=0

  while IFS= read -r share; do
    if mount_smb_share "$share" "$server" "$display_name" "$username" "$password" "$mount_base"; then
      ((mounted_count++))
    else
      ((failed_count++))
    fi
  done <<< "$shares"

  # Summary
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_success "Montés: $mounted_count/$share_count"

  if [[ $failed_count -gt 0 ]]; then
    log_error "Échecs: $failed_count"
  fi

  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Reload Finder to make mounted shares appear in sidebar immediately
  # Execute if at least one share was successfully mounted
  if [[ "$DRY_RUN" != "true" ]] && [[ $mounted_count -gt 0 ]]; then
    log_info "Rechargement du Finder pour afficher les partages..."
    # Kill Finder process (it will auto-restart on macOS)
    /usr/bin/killall Finder 2>/dev/null
    # Wait a moment for Finder to fully restart
    sleep 1
    # Ensure Finder is running
    /usr/bin/open -a Finder 2>/dev/null
    log_success "Finder rechargé avec succès"
  fi

  # Return failure if any mounts failed
  if [[ $failed_count -gt 0 ]]; then
    return 1
  fi

  return 0
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_nas_automount() {
  log_section "Configuration du montage automatique NAS"

  # Check if running with --mount-only flag (LaunchAgent mode)
  local mount_only=false
  for arg in "$@"; do
    if [[ "$arg" == "--mount-only" ]]; then
      mount_only=true
      break
    fi
  done

  if [[ "$mount_only" == "true" ]]; then
    # Called by LaunchAgent - just mount shares
    mount_nas_shares
    return $?
  fi

  # Check if already configured
  local config
  config=$(read_nas_config)

  IFS='|' read -r server display_name username mount_base wait_timeout <<< "$config"

  if [[ -n "$server" ]] && [[ -n "$username" ]]; then
    # Configuration exists - show menu with 3 choices
    if [[ "$DRY_RUN" == "true" ]]; then
      # In dry-run mode, just report existing config
      log_info "Configuration NAS détectée (mode dry-run)"
      log_success "Serveur: $display_name"
      log_success "Utilisateur: $username"
      log_info "En mode normal, un menu de choix serait affiché"
      return 0
    fi

    # Show menu and get user choice (returns "1", "2", or "3")
    local choice
    choice=$(show_config_choice_menu "$display_name" "$username")

    case "$choice" in
      1)
        # Choice 1: Reuse existing config
        reuse_existing_config "$server" "$username"
        return $?
        ;;
      2)
        # Choice 2: Reconfigure completely (with pre-filled values)
        log_info "Reconfiguration complète..."
        do_interactive_setup "$server" "$username"
        return $?
        ;;
      3)
        # Choice 3: Cancel
        log_info "Configuration ignorée (annulée par l'utilisateur)"
        return 0
        ;;
      *)
        # Unexpected result - fallback to reuse
        log_warning "Résultat inattendu du menu, réutilisation de la config"
        reuse_existing_config "$server" "$username"
        return $?
        ;;
    esac
  else
    # First time setup
    do_interactive_setup
    return $?
  fi
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_nas_automount "$@"
fi
