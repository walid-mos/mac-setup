#!/usr/bin/env bash

# ============================================================================
# NAS Auto-Mount Setup
# Configures automatic mounting of SMB/NAS shares using mount_smbfs directly.
# No external dependencies (no nasreco, no subshells).
#
# SECURITY NOTICE:
# - Passwords are stored ONLY in macOS Keychain (AES-256-GCM encryption)
# - Passwords are NEVER written to TOML files, logs, or temporary files
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

# ============================================================================
# Mount Functions (replaces nasreco - no subshells needed)
# ============================================================================

# URL-encode a string for SMB URLs
url_encode() {
  local string="$1"
  if command -v perl &>/dev/null; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$string"
  else
    # Basic encoding for common special chars
    echo "$string" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g'
  fi
}

# Get password from macOS Keychain
get_keychain_password() {
  local service="$1"
  security find-generic-password -w -s "$service" 2>/dev/null || echo ""
}

# Store password in macOS Keychain
store_keychain_password() {
  local server="$1"
  local username="$2"
  local password="$3"
  local service="${KEYCHAIN_SERVICE_PREFIX}-${server}"

  # Delete existing entry if present
  security delete-generic-password -s "$service" 2>/dev/null || true

  # Add new entry
  local error_output
  if ! error_output=$(security add-generic-password \
    -s "$service" \
    -l "NAS SMB mount for $server" \
    -w "$password" \
    -U 2>&1); then
    log_error "Failed to store password in Keychain: $error_output"
    return 1
  fi

  log_verbose "Credentials stored in Keychain: $service"
  return 0
}

# Mount a single SMB share
mount_single_share() {
  local server="$1"
  local share="$2"
  local username="$3"
  local password="$4"
  local mount_base="${5:-/Volumes}"

  local mount_point="${mount_base}/${share}"

  # Check if already mounted
  if mount | grep -q " on ${mount_point} "; then
    log_verbose "Already mounted: $share"
    return 0
  fi

  # Create mount point if needed
  if [[ ! -d "$mount_point" ]]; then
    mkdir -p "$mount_point" 2>/dev/null || sudo mkdir -p "$mount_point"
  fi

  # URL-encode password
  local encoded_password
  encoded_password=$(url_encode "$password")

  # Mount using mount_smbfs
  local smb_url="//${username}:${encoded_password}@${server}/${share}"

  if mount_smbfs "$smb_url" "$mount_point" 2>/dev/null; then
    log_success "Mounted: $share -> $mount_point"
    return 0
  else
    log_error "Failed to mount: $share"
    # Cleanup empty mount point
    rmdir "$mount_point" 2>/dev/null || true
    return 1
  fi
}

# Mount all configured shares
mount_all_shares() {
  local verbose="${1:-false}"

  # Read config from TOML
  local server username mount_base shares_raw
  server=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.server" 2>/dev/null | tr -d "'\"")
  username=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.username" 2>/dev/null | tr -d "'\"")
  mount_base=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.mount_base" 2>/dev/null | tr -d "'\"")
  mount_base="${mount_base:-/Volumes}"

  if [[ -z "$server" ]] || [[ -z "$username" ]]; then
    log_error "NAS configuration not found in TOML"
    return 1
  fi

  # Get password from Keychain
  local service="${KEYCHAIN_SERVICE_PREFIX}-${server}"
  local password
  password=$(get_keychain_password "$service")

  if [[ -z "$password" ]]; then
    log_error "Could not retrieve NAS password from Keychain"
    log_error "Expected service name: $service"
    log_info "Store password with: security add-generic-password -s '$service' -w 'PASSWORD'"
    return 1
  fi

  # Check server reachability
  if ! ping -c 1 -W 2 "$server" &>/dev/null; then
    [[ "$verbose" == "true" ]] && log_warning "Server unreachable: $server"
    return 1
  fi

  # Get shares list from TOML
  local shares
  shares=$(parse_toml_array "$TOML_CONFIG" "automations.nas-shares.shares" 2>/dev/null | tr -d "'\"")

  if [[ -z "$shares" ]]; then
    log_error "No shares configured in TOML"
    return 1
  fi

  [[ "$verbose" == "true" ]] && log_info "NAS Server: $server"
  [[ "$verbose" == "true" ]] && log_info "Username: $username"
  [[ "$verbose" == "true" ]] && log_info "Shares: $(echo "$shares" | tr '\n' ' ')"

  # Mount each share
  local success=0
  local failed=0
  while IFS= read -r share; do
    [[ -z "$share" ]] && continue
    if mount_single_share "$server" "$share" "$username" "$password" "$mount_base"; then
      ((success++))
    else
      ((failed++))
    fi
  done <<< "$shares"

  [[ "$verbose" == "true" ]] && log_info "Mounted: $success, Failed: $failed"

  [[ $failed -eq 0 ]]
}

# ============================================================================
# SMB Discovery Functions
# ============================================================================

# List available shares on SMB server
list_smb_shares() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_step "Découverte des partages disponibles sur $server..." >&2

  server="${server#smb://}"
  server="${server#//}"

  if ! ping -c 1 -W 2 "$server" &>/dev/null; then
    log_error "Serveur inaccessible: $server" >&2
    return 1
  fi

  local encoded_password
  encoded_password=$(url_encode "$password")

  local smbutil_output
  smbutil_output=$(smbutil view "//${username}:${encoded_password}@${server}" 2>&1) || {
    log_error "Impossible de se connecter au serveur SMB: $server" >&2
    return 1
  }

  local shares
  shares=$(echo "$smbutil_output" | grep "Disk" | awk '{print $1}' | grep -v "^$")

  if [[ -z "$shares" ]]; then
    log_error "Aucun partage disponible sur $server" >&2
    return 1
  fi

  echo "$shares"
}

# Interactive share selection with fzf
select_shares_interactive() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_subsection "Sélection interactive des partages" >&2

  if ! command -v fzf &>/dev/null; then
    log_error "fzf n'est pas installé" >&2
    return 1
  fi

  local available_shares
  available_shares=$(list_smb_shares "$server" "$username" "$password") || return 1

  local share_count
  share_count=$(echo "$available_shares" | wc -l | xargs)
  log_success "$share_count partages découverts" >&2

  local selected
  selected=$(echo "$available_shares" | fzf \
    --multi \
    --height=60% \
    --border \
    --prompt="Sélectionnez les partages (TAB pour multi, ENTER pour confirmer): " \
    --header="$share_count partages sur $server")

  [[ -z "$selected" ]] && return 1
  echo "$selected"
}

# ============================================================================
# LaunchAgent & Sleepwatcher
# ============================================================================

create_launchagent() {
  log_step "Création du LaunchAgent..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would create: $LAUNCHAGENT_PLIST"; return 0; }

  mkdir -p "$HOME/Library/LaunchAgents"

  # LaunchAgent calls THIS script with --mount flag (no subshells!)
  cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHAGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${SCRIPT_DIR}/setup-nas-automount.sh</string>
    <string>--mount</string>
  </array>

  <key>RunAtLoad</key>
  <true/>

  <key>StartInterval</key>
  <integer>300</integer>

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

  log_success "LaunchAgent créé: $LAUNCHAGENT_PLIST"
}

install_launchagent() {
  log_step "Installation du LaunchAgent..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would load: $LAUNCHAGENT_PLIST"; return 0; }

  launchctl list 2>/dev/null | grep -q "$LAUNCHAGENT_LABEL" && \
    launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true

  if launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null; then
    log_success "LaunchAgent installé et activé"
  else
    log_error "Échec du chargement du LaunchAgent"
    return 1
  fi
}

setup_sleepwatcher() {
  log_step "Configuration de sleepwatcher..."

  if ! command -v sleepwatcher &>/dev/null; then
    log_info "sleepwatcher n'est pas installé"
    [[ "$DRY_RUN" == "true" ]] && return 0

    read -r -p "Installer sleepwatcher pour reconnexion au réveil ? (O/n): " install_sw
    if [[ -z "$install_sw" ]] || [[ "$install_sw" =~ ^[oOyY]$ ]]; then
      brew install sleepwatcher
      brew services start sleepwatcher
      log_success "sleepwatcher installé"
    else
      return 0
    fi
  fi

  local wakeup_script="$HOME/.wakeup"
  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would create: $wakeup_script"; return 0; }

  # Wakeup script calls THIS script directly (no subshells!)
  cat > "$wakeup_script" << EOF
#!/bin/bash
# Reconnect NAS shares after wake from sleep
sleep 3
${SCRIPT_DIR}/setup-nas-automount.sh --mount 2>/dev/null
EOF

  chmod +x "$wakeup_script"
  log_success "Script de réveil créé: $wakeup_script"

  pgrep -q sleepwatcher || brew services start sleepwatcher 2>/dev/null || true
  log_success "sleepwatcher configuré"
}

# ============================================================================
# TOML Config Management
# ============================================================================

update_toml_config() {
  local server="$1"
  local username="$2"
  local shares="$3"
  local mount_base="${4:-/Volumes}"

  log_step "Mise à jour de la configuration TOML..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would update TOML"; return 0; }

  grep -q "\[automations.nas-shares\]" "$TOML_CONFIG" 2>/dev/null && {
    log_warning "Section [automations.nas-shares] existe déjà"
    return 0
  }

  local shares_array="["
  local first=true
  while IFS= read -r share; do
    [[ -z "$share" ]] && continue
    [[ "$first" == "true" ]] && { shares_array+="\"$share\""; first=false; } || shares_array+=", \"$share\""
  done <<< "$shares"
  shares_array+="]"

  cat >> "$TOML_CONFIG" << EOF

# -----------------------------------------------------------------------------
# NAS Auto-Mount Configuration
# -----------------------------------------------------------------------------
[automations.nas-shares]
enabled = true
server = "$server"
username = "$username"
mount_base = "$mount_base"
shares = $shares_array
EOF

  log_success "Configuration TOML mise à jour"
}

read_nas_config() {
  local server username
  server=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.server" 2>/dev/null | tr -d "'\"")
  username=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.username" 2>/dev/null | tr -d "'\"")
  echo "$server|$username"
}

# ============================================================================
# Interactive Setup
# ============================================================================

do_interactive_setup() {
  local existing_server="${1:-}"
  local existing_username="${2:-}"

  log_subsection "Configuration interactive du montage NAS"

  # Step 1: Get NAS server
  log_step "Configuration du serveur NAS"
  local nas_server
  if [[ -n "$existing_server" ]]; then
    read -r -p "Adresse du serveur NAS [$existing_server]: " nas_server
    nas_server="${nas_server:-$existing_server}"
  else
    read -r -p "Adresse du serveur NAS (ex: 192.168.1.100): " nas_server
  fi

  [[ -z "$nas_server" ]] && { log_error "Serveur requis"; return 1; }
  nas_server="${nas_server#smb://}"
  nas_server="${nas_server#//}"
  log_success "Serveur: $nas_server"

  # Step 2: Get credentials
  log_step "Configuration des identifiants"
  local nas_username
  if [[ -n "$existing_username" ]]; then
    read -r -p "Nom d'utilisateur [$existing_username]: " nas_username
    nas_username="${nas_username:-$existing_username}"
  else
    read -r -p "Nom d'utilisateur: " nas_username
  fi

  [[ -z "$nas_username" ]] && { log_error "Username requis"; return 1; }

  local nas_password
  read -r -s -p "Mot de passe: " nas_password
  echo ""
  [[ -z "$nas_password" ]] && { log_error "Password requis"; return 1; }
  log_success "Identifiants configurés"

  # Step 3: Select shares
  local selected_shares
  selected_shares=$(select_shares_interactive "$nas_server" "$nas_username" "$nas_password") || {
    log_error "Aucun partage sélectionné"
    return 1
  }

  # Step 4: Store credentials
  log_step "Stockage des identifiants dans le Keychain..."
  if [[ "$DRY_RUN" != "true" ]]; then
    if store_keychain_password "$nas_server" "$nas_username" "$nas_password"; then
      log_success "Identifiants stockés"
    else
      log_error "Échec du stockage"
      log_info "Essayez: security add-generic-password -s 'nas-share-$nas_server' -w 'PASSWORD'"
      return 1
    fi
  fi

  # Step 5: Update TOML
  update_toml_config "$nas_server" "$nas_username" "$selected_shares"

  # Step 6: Setup LaunchAgent & sleepwatcher
  create_launchagent
  install_launchagent
  echo ""
  setup_sleepwatcher

  # Step 7: Offer to test
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  Configuration terminée !"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$DRY_RUN" != "true" ]]; then
    read -r -p "Monter les partages maintenant ? (O/n): " do_mount
    if [[ -z "$do_mount" ]] || [[ "$do_mount" =~ ^[oOyY]$ ]]; then
      echo ""
      log_subsection "Test du montage"
      mount_all_shares true
    fi
  fi
}

# ============================================================================
# Main
# ============================================================================

automation_setup_nas_automount() {
  # Handle --mount flag (called by LaunchAgent/sleepwatcher - NO OUTPUT)
  for arg in "$@"; do
    if [[ "$arg" == "--mount" ]]; then
      mount_all_shares false
      return $?
    fi
    if [[ "$arg" == "--mount-verbose" ]]; then
      mount_all_shares true
      return $?
    fi
  done

  log_section "Configuration du montage automatique NAS"

  local config server username
  config=$(read_nas_config)
  IFS='|' read -r server username <<< "$config"

  if [[ -n "$server" ]] && [[ -n "$username" ]]; then
    # Config exists
    [[ "$DRY_RUN" == "true" ]] && {
      log_info "Configuration NAS détectée (dry-run)"
      log_success "Serveur: $server"
      log_success "Utilisateur: $username"
      return 0
    }

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  Configuration NAS existante"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Serveur: $server"
    log_success "Utilisateur: $username"
    echo ""

    if command -v fzf &>/dev/null; then
      local choice
      choice=$(printf '%s\n' \
        "1|Monter les partages|Monte maintenant avec la config existante" \
        "2|Reconfigurer|Redemande serveur, credentials et partages" \
        "3|Annuler|Ne rien faire" | fzf \
        --height=40% \
        --border=rounded \
        --prompt="Action ? " \
        --delimiter="|" \
        --with-nth=2 \
        --preview='echo {3}' \
        --preview-window=down:2:wrap | cut -d'|' -f1)

      case "$choice" in
        1)
          [[ ! -f "$LAUNCHAGENT_PLIST" ]] && { create_launchagent; install_launchagent; }
          echo ""
          log_subsection "Montage des partages"
          mount_all_shares true
          ;;
        2) do_interactive_setup "$server" "$username" ;;
        *) log_info "Annulé" ;;
      esac
    else
      read -r -p "Reconfigurer ? (o/N): " reconfig
      if [[ "$reconfig" =~ ^[oOyY]$ ]]; then
        do_interactive_setup "$server" "$username"
      else
        [[ ! -f "$LAUNCHAGENT_PLIST" ]] && { create_launchagent; install_launchagent; }
        mount_all_shares true
      fi
    fi
  else
    do_interactive_setup
  fi
}

# ============================================================================
# Entry Point
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_nas_automount "$@"
fi
