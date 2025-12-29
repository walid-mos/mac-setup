#!/usr/bin/env bash

# ============================================================================
# NAS Auto-Mount Setup
# Configures automatic mounting of SMB/NAS shares using mount_smbfs directly.
#
# ARCHITECTURE:
# - Generates a standalone mount script at ~/.local/bin/mount-nas.sh
# - Config is hardcoded in the generated script (no external config files)
# - Password stored in macOS Keychain (AES-256-GCM encryption)
# - LaunchAgent and sleepwatcher point to the generated script
#
# SECURITY NOTICE:
# - Passwords are stored ONLY in macOS Keychain
# - Passwords are NEVER written to files, logs, or temporary storage
# ============================================================================

set -euo pipefail
set +o history  # Disable shell history to prevent password leakage

# Source required libraries (only for interactive setup)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
fi

# ============================================================================
# Configuration
# ============================================================================
MOUNT_SCRIPT_PATH="$HOME/.local/bin/mount-nas.sh"
LAUNCHAGENT_LABEL="com.user.nas-automount"
LAUNCHAGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCHAGENT_LABEL}.plist"
KEYCHAIN_SERVICE_PREFIX="nas-share"
DEFAULT_MOUNT_BASE="$HOME/NAS"

# ============================================================================
# Standalone Script Detection
# ============================================================================

# Detect existing configuration from generated script
detect_existing_config() {
  [[ ! -f "$MOUNT_SCRIPT_PATH" ]] && return 1

  local server username mount_base shares
  server=$(grep '^# Server:' "$MOUNT_SCRIPT_PATH" 2>/dev/null | cut -d: -f2- | xargs) || true
  username=$(grep '^# Username:' "$MOUNT_SCRIPT_PATH" 2>/dev/null | cut -d: -f2- | xargs) || true
  mount_base=$(grep '^# Mount Base:' "$MOUNT_SCRIPT_PATH" 2>/dev/null | cut -d: -f2- | xargs) || true
  shares=$(grep '^# Shares:' "$MOUNT_SCRIPT_PATH" 2>/dev/null | cut -d: -f2- | xargs) || true

  [[ -z "$server" ]] && return 1

  echo "${server}|${username}|${mount_base}|${shares}"
}

# ============================================================================
# Standalone Script Generation
# ============================================================================

# Generate the standalone mount script with hardcoded values
generate_mount_script() {
  local server="$1"
  local username="$2"
  local mount_base="$3"
  local shares="$4"  # Newline-separated

  log_step "Generation du script de montage..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would generate: $MOUNT_SCRIPT_PATH"; return 0; }

  # Prepare shares for script
  local shares_csv
  shares_csv=$(echo "$shares" | tr '\n' ',' | sed 's/,$//')

  local shares_array=""
  while IFS= read -r share; do
    [[ -z "$share" ]] && continue
    shares_array+="\"$share\" "
  done <<< "$shares"

  # Create directory
  mkdir -p "$(dirname "$MOUNT_SCRIPT_PATH")"

  # Generate the standalone script
  cat > "$MOUNT_SCRIPT_PATH" << 'SCRIPT_HEADER'
#!/usr/bin/env bash
# ============================================================================
# NAS Auto-Mount Script (Generated)
# ============================================================================
SCRIPT_HEADER

  cat >> "$MOUNT_SCRIPT_PATH" << EOF
# Server: ${server}
# Username: ${username}
# Mount Base: ${mount_base}
# Shares: ${shares_csv}
# Generated: $(date -Iseconds)
# ============================================================================

set -euo pipefail

# Configuration (hardcoded at generation time)
SERVER="${server}"
USERNAME="${username}"
MOUNT_BASE="${mount_base}"
SHARES=(${shares_array})
KEYCHAIN_SERVICE="nas-share-\${SERVER}"

EOF

  cat >> "$MOUNT_SCRIPT_PATH" << 'SCRIPT_BODY'
# URL-encode a string for SMB URLs
url_encode() {
  local string="$1"
  if command -v perl &>/dev/null; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$string"
  else
    echo "$string" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g'
  fi
}

# Get password from macOS Keychain
get_password() {
  security find-generic-password -w -s "$KEYCHAIN_SERVICE" -a "$USERNAME" 2>/dev/null
}

# Mount a single share
mount_share() {
  local share="$1"
  local verbose="${2:-false}"
  local mount_point="${MOUNT_BASE}/${share}"

  # Skip if already mounted
  if mount | grep -q " on ${mount_point} "; then
    [[ "$verbose" == "true" ]] && echo "[OK] Already mounted: $share"
    return 0
  fi

  # Create mount point if needed
  if [[ ! -d "$mount_point" ]]; then
    mkdir -p "$mount_point" 2>/dev/null || sudo mkdir -p "$mount_point"
  fi

  # Get password and mount
  local password
  password=$(get_password) || {
    [[ "$verbose" == "true" ]] && echo "[ERROR] No password in Keychain for $KEYCHAIN_SERVICE"
    return 1
  }

  local encoded_password
  encoded_password=$(url_encode "$password")

  if mount_smbfs "//${USERNAME}:${encoded_password}@${SERVER}/${share}" "$mount_point" 2>/dev/null; then
    [[ "$verbose" == "true" ]] && echo "[OK] Mounted: $share -> $mount_point"
    return 0
  else
    [[ "$verbose" == "true" ]] && echo "[ERROR] Failed to mount: $share"
    rmdir "$mount_point" 2>/dev/null || true
    return 1
  fi
}

# Main
main() {
  local verbose=false
  [[ "${1:-}" == "--verbose" ]] && verbose=true

  # Check server reachability (silent exit if unreachable)
  if ! ping -c 1 -W 2 "$SERVER" &>/dev/null; then
    [[ "$verbose" == "true" ]] && echo "[WARN] Server unreachable: $SERVER"
    exit 0
  fi

  local success=0
  local failed=0

  for share in "${SHARES[@]}"; do
    if mount_share "$share" "$verbose"; then
      ((success++))
    else
      ((failed++))
    fi
  done

  [[ "$verbose" == "true" ]] && echo "[INFO] Mounted: $success, Failed: $failed"
  [[ $failed -eq 0 ]]
}

main "$@"
SCRIPT_BODY

  chmod +x "$MOUNT_SCRIPT_PATH"
  log_success "Script genere: $MOUNT_SCRIPT_PATH"
}

# ============================================================================
# Helper Functions
# ============================================================================

# URL-encode a string for SMB URLs
url_encode() {
  local string="$1"
  if command -v perl &>/dev/null; then
    perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$string"
  else
    echo "$string" | sed 's/%/%25/g; s/ /%20/g; s/!/%21/g; s/"/%22/g; s/#/%23/g; s/\$/%24/g; s/&/%26/g; s/'\''/%27/g; s/(/%28/g; s/)/%29/g; s/*/%2A/g; s/+/%2B/g; s/,/%2C/g; s/:/%3A/g; s/;/%3B/g; s/=/%3D/g; s/?/%3F/g; s/@/%40/g'
  fi
}

# Store password in macOS Keychain
store_keychain_password() {
  local server="$1"
  local username="$2"
  local password="$3"
  local service="${KEYCHAIN_SERVICE_PREFIX}-${server}"

  # Delete existing entry if present
  security delete-generic-password -s "$service" -a "$username" 2>/dev/null || true

  # Add new entry
  local error_output
  if ! error_output=$(security add-generic-password \
    -s "$service" \
    -a "$username" \
    -l "NAS SMB mount for $server" \
    -w "$password" \
    -U 2>&1); then
    log_error "Failed to store password in Keychain: $error_output"
    return 1
  fi

  log_verbose "Credentials stored in Keychain: $service"
  return 0
}

# ============================================================================
# SMB Discovery Functions
# ============================================================================

# List available shares on SMB server
list_smb_shares() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_step "Decouverte des partages disponibles sur $server..." >&2

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

  log_subsection "Selection interactive des partages" >&2

  if ! command -v fzf &>/dev/null; then
    log_error "fzf n'est pas installe" >&2
    return 1
  fi

  local available_shares
  available_shares=$(list_smb_shares "$server" "$username" "$password") || return 1

  local share_count
  share_count=$(echo "$available_shares" | wc -l | xargs)
  log_success "$share_count partages decouverts" >&2

  local selected
  selected=$(echo "$available_shares" | fzf \
    --multi \
    --height=60% \
    --border \
    --prompt="Selectionnez les partages (TAB pour multi, ENTER pour confirmer): " \
    --header="$share_count partages sur $server")

  [[ -z "$selected" ]] && return 1
  echo "$selected"
}

# ============================================================================
# LaunchAgent & Sleepwatcher
# ============================================================================

create_launchagent() {
  log_step "Creation du LaunchAgent..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would create: $LAUNCHAGENT_PLIST"; return 0; }

  mkdir -p "$HOME/Library/LaunchAgents"

  # LaunchAgent calls the GENERATED standalone script
  cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHAGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${MOUNT_SCRIPT_PATH}</string>
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

  log_success "LaunchAgent cree: $LAUNCHAGENT_PLIST"
}

install_launchagent() {
  log_step "Installation du LaunchAgent..."

  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would load: $LAUNCHAGENT_PLIST"; return 0; }

  launchctl list 2>/dev/null | grep -q "$LAUNCHAGENT_LABEL" && \
    launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true

  if launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null; then
    log_success "LaunchAgent installe et active"
  else
    log_error "Echec du chargement du LaunchAgent"
    return 1
  fi
}

setup_sleepwatcher() {
  log_step "Configuration de sleepwatcher..."

  if ! command -v sleepwatcher &>/dev/null; then
    log_info "sleepwatcher n'est pas installe"
    [[ "$DRY_RUN" == "true" ]] && return 0

    read -r -p "Installer sleepwatcher pour reconnexion au reveil ? (O/n): " install_sw
    if [[ -z "$install_sw" ]] || [[ "$install_sw" =~ ^[oOyY]$ ]]; then
      brew install sleepwatcher
      brew services start sleepwatcher
      log_success "sleepwatcher installe"
    else
      return 0
    fi
  fi

  local wakeup_script="$HOME/.wakeup"
  [[ "$DRY_RUN" == "true" ]] && { log_info "[DRY RUN] Would create: $wakeup_script"; return 0; }

  # Wakeup script calls the GENERATED standalone script
  cat > "$wakeup_script" << EOF
#!/bin/bash
# Reconnect NAS shares after wake from sleep
sleep 3
${MOUNT_SCRIPT_PATH} 2>/dev/null
EOF

  chmod +x "$wakeup_script"
  log_success "Script de reveil cree: $wakeup_script"

  pgrep -q sleepwatcher || brew services start sleepwatcher 2>/dev/null || true
  log_success "sleepwatcher configure"
}

# ============================================================================
# Interactive Setup
# ============================================================================

do_interactive_setup() {
  local existing_server="${1:-}"
  local existing_username="${2:-}"
  local existing_mount_base="${3:-$DEFAULT_MOUNT_BASE}"

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
  log_success "Identifiants configures"

  # Step 3: Select shares
  local selected_shares
  selected_shares=$(select_shares_interactive "$nas_server" "$nas_username" "$nas_password") || {
    log_error "Aucun partage selectionne"
    return 1
  }

  # Step 4: Store credentials in Keychain
  log_step "Stockage des identifiants dans le Keychain..."
  if [[ "$DRY_RUN" != "true" ]]; then
    if store_keychain_password "$nas_server" "$nas_username" "$nas_password"; then
      log_success "Identifiants stockes"
    else
      log_error "Echec du stockage"
      log_info "Essayez: security add-generic-password -s 'nas-share-$nas_server' -a '$nas_username' -w 'PASSWORD'"
      return 1
    fi
  fi

  # Step 5: Generate standalone mount script
  generate_mount_script "$nas_server" "$nas_username" "$existing_mount_base" "$selected_shares"

  # Step 6: Setup LaunchAgent & sleepwatcher
  create_launchagent
  install_launchagent
  echo ""
  setup_sleepwatcher

  # Step 7: Offer to test
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  Configuration terminee !"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ "$DRY_RUN" != "true" ]]; then
    read -r -p "Monter les partages maintenant ? (O/n): " do_mount
    if [[ -z "$do_mount" ]] || [[ "$do_mount" =~ ^[oOyY]$ ]]; then
      echo ""
      log_subsection "Test du montage"
      "$MOUNT_SCRIPT_PATH" --verbose
    fi
  fi
}

# ============================================================================
# Main
# ============================================================================

automation_setup_nas_automount() {
  # Handle --mount flag: redirect to standalone script if it exists
  for arg in "$@"; do
    if [[ "$arg" == "--mount" ]] || [[ "$arg" == "--mount-verbose" ]]; then
      if [[ -x "$MOUNT_SCRIPT_PATH" ]]; then
        [[ "$arg" == "--mount-verbose" ]] && exec "$MOUNT_SCRIPT_PATH" --verbose
        exec "$MOUNT_SCRIPT_PATH"
      else
        log_error "Mount script not found: $MOUNT_SCRIPT_PATH"
        log_info "Run the setup first to generate the mount script"
        return 1
      fi
    fi
  done

  log_section "Configuration du montage automatique NAS"

  # Check for existing configuration in generated script
  local existing_config
  if existing_config=$(detect_existing_config); then
    IFS='|' read -r existing_server existing_user existing_base existing_shares <<< "$existing_config"

    [[ "$DRY_RUN" == "true" ]] && {
      log_info "Configuration NAS detectee (dry-run)"
      log_success "Serveur: $existing_server"
      log_success "Utilisateur: $existing_user"
      log_success "Shares: $existing_shares"
      return 0
    }

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  Configuration NAS existante"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Serveur: $existing_server"
    log_success "Utilisateur: $existing_user"
    log_success "Shares: $existing_shares"
    log_success "Script: $MOUNT_SCRIPT_PATH"
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
          "$MOUNT_SCRIPT_PATH" --verbose
          ;;
        2) do_interactive_setup "$existing_server" "$existing_user" "$existing_base" ;;
        *) log_info "Annule" ;;
      esac
    else
      read -r -p "Reutiliser cette configuration ? (O/n): " reuse
      if [[ -z "$reuse" ]] || [[ "$reuse" =~ ^[oOyY]$ ]]; then
        [[ ! -f "$LAUNCHAGENT_PLIST" ]] && { create_launchagent; install_launchagent; }
        "$MOUNT_SCRIPT_PATH" --verbose
      else
        do_interactive_setup "$existing_server" "$existing_user" "$existing_base"
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
