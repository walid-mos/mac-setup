#!/usr/bin/env bash

# ============================================================================
# NAS Auto-Mount Setup
# Configures automatic mounting of SMB/NAS shares at startup
# ============================================================================

set -euo pipefail

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

  log_step "Découverte des partages disponibles sur $server..."

  # Remove smb:// prefix if present
  server="${server#smb://}"
  server="${server#//}"

  # Use smbutil to list shares
  local shares
  if [[ -n "$password" ]]; then
    # With authentication
    shares=$(smbutil view -A "//${username}:${password}@${server}" 2>/dev/null | \
      grep "Disk" | awk '{print $1}' | grep -v "^$" || echo "")
  else
    # Try without authentication (guest)
    shares=$(smbutil view "//${server}" 2>/dev/null | \
      grep "Disk" | awk '{print $1}' | grep -v "^$" || echo "")
  fi

  if [[ -z "$shares" ]]; then
    log_error "Impossible de lister les partages sur $server"
    log_info "Vérifiez que le serveur est accessible et que les credentials sont corrects"
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

  log_subsection "Sélection interactive des partages"

  # Check if fzf is available
  if ! command_exists fzf; then
    log_error "fzf n'est pas installé (requis pour la sélection interactive)"
    log_info "fzf devrait être installé via le module brew-packages"
    return 1
  fi

  # List available shares
  local available_shares
  available_shares=$(list_smb_shares "$server" "$username" "$password")

  if [[ -z "$available_shares" ]]; then
    return 1
  fi

  local share_count
  share_count=$(echo "$available_shares" | wc -l | xargs)
  log_success "$share_count partages découverts"

  # Display shares and use fzf for multi-selection
  local selected
  selected=$(echo "$available_shares" | fzf \
    --multi \
    --height=60% \
    --border \
    --prompt="Sélectionnez les partages à monter automatiquement (TAB pour sélectionner, ENTER pour confirmer): " \
    --header="Partages disponibles sur $server" \
    --preview="echo 'Sera monté dans: /Volumes/{}'" \
    --preview-window=down:3:wrap)

  if [[ -z "$selected" ]]; then
    log_warning "Aucun partage sélectionné"
    return 1
  fi

  local selected_count
  selected_count=$(echo "$selected" | wc -l | xargs)
  log_success "$selected_count partages sélectionnés"

  echo "$selected"
  return 0
}

# Mount a single SMB share
mount_smb_share() {
  local share_name="$1"
  local server="$2"
  local username="$3"
  local password="$4"
  local mount_base="$5"

  local mountpoint="${mount_base}/${share_name}"

  log_step "Montage: $share_name"

  # Check if already mounted
  if is_share_mounted "$mountpoint"; then
    log_success "Déjà monté: $mountpoint"
    return 0
  fi

  # Ensure mount point exists
  if [[ ! -d "$mountpoint" ]]; then
    log_verbose "Création du point de montage: $mountpoint"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would create: $mountpoint"
    else
      mkdir -p "$mountpoint" || {
        log_error "Impossible de créer le point de montage: $mountpoint"
        return 1
      }
    fi
  fi

  # URL-encode password for special characters
  local encoded_password
  encoded_password=$(url_encode "$password")

  # Remove smb:// prefix if present
  server="${server#smb://}"
  server="${server#//}"

  # Build mount URL
  local mount_url="//${username}:${encoded_password}@${server}/${share_name}"

  # Mount options (optimized for reliability and performance)
  local mount_options="automounted,nobrowse,soft"

  # Mount the share
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: mount -t smbfs -o $mount_options '//user:***@${server}/${share_name}' '$mountpoint'"
    return 0
  fi

  if mount -t smbfs -o "$mount_options" "$mount_url" "$mountpoint" 2>/dev/null; then
    log_success "Monté: $share_name → $mountpoint"
    return 0
  else
    log_error "Échec du montage: $share_name"
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
  local username="$2"
  local shares="$3"
  local mount_base="$4"

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
  local config_server config_username config_mount_base config_wait_timeout

  config_server=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.server" 2>/dev/null || echo "")
  config_username=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.username" 2>/dev/null || echo "")
  config_mount_base=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.mount_base" 2>/dev/null || echo "$DEFAULT_MOUNT_BASE")
  config_wait_timeout=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.wait_timeout" 2>/dev/null || echo "$DEFAULT_WAIT_TIMEOUT")

  echo "$config_server|$config_username|$config_mount_base|$config_wait_timeout"
}

# Read shares list from TOML
read_shares_from_toml() {
  parse_toml_array "$TOML_CONFIG" "automations.nas-shares.shares" 2>/dev/null || echo ""
}

# ============================================================================
# Main Functions
# ============================================================================

# Interactive setup (first-time configuration)
setup_nas_interactive() {
  log_subsection "Configuration interactive du montage NAS"

  # Step 1: Get NAS server
  log_step "Configuration du serveur NAS"

  echo ""
  read -r -p "Entrez l'adresse du serveur NAS (ex: Ours-Imposant, nas.local, 192.168.1.100): " nas_server

  if [[ -z "$nas_server" ]]; then
    log_error "Serveur NAS requis"
    return 1
  fi

  # Remove smb:// prefix if user entered it
  nas_server="${nas_server#smb://}"
  nas_server="${nas_server#//}"

  log_success "Serveur NAS: $nas_server"

  # Step 2: Get credentials
  log_step "Configuration des identifiants"

  echo ""
  read -r -p "Nom d'utilisateur NAS: " nas_username

  if [[ -z "$nas_username" ]]; then
    log_error "Nom d'utilisateur requis"
    return 1
  fi

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
  update_toml_config "$nas_server" "$nas_username" "$selected_shares" "$DEFAULT_MOUNT_BASE"

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
    read -r -p "Voulez-vous monter les partages maintenant ? (o/N): " test_mount

    if [[ "$test_mount" =~ ^[oOyY]$ ]]; then
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

  IFS='|' read -r server username mount_base wait_timeout <<< "$config"

  if [[ -z "$server" ]] || [[ -z "$username" ]]; then
    log_error "Configuration NAS non trouvée dans $TOML_CONFIG"
    log_info "Exécutez d'abord la configuration interactive"
    return 1
  fi

  log_info "Serveur: $server"
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
    if mount_smb_share "$share" "$server" "$username" "$password" "$mount_base"; then
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
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    return 1
  fi

  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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

  IFS='|' read -r server username mount_base wait_timeout <<< "$config"

  if [[ -n "$server" ]] && [[ -n "$username" ]]; then
    log_info "Configuration NAS détectée"
    log_success "Serveur: $server"
    log_success "Utilisateur: $username"

    # Check if LaunchAgent exists
    if [[ -f "$LAUNCHAGENT_PLIST" ]]; then
      log_success "LaunchAgent installé"
    else
      log_warning "LaunchAgent non trouvé, recréation..."
      local script_path="$SCRIPT_DIR/$(basename "$0")"
      create_launchagent "$script_path"
      install_launchagent
    fi

    # Ask if user wants to reconfigure
    if [[ "$DRY_RUN" != "true" ]]; then
      echo ""
      read -r -p "Voulez-vous reconfigurer ? (o/N): " reconfigure

      if [[ "$reconfigure" =~ ^[oOyY]$ ]]; then
        setup_nas_interactive
        return $?
      fi
    fi

    log_success "Configuration NAS déjà en place"
    return 0
  else
    # First time setup
    setup_nas_interactive
    return $?
  fi
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_nas_automount "$@"
fi
