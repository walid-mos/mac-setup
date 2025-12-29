#!/usr/bin/env bash

# ============================================================================
# NAS Auto-Mount Setup
# Configures automatic mounting of SMB/NAS shares using nasreco (from stow dotfiles)
#
# ARCHITECTURE:
# This script handles SETUP only (credentials, LaunchAgent, sleepwatcher).
# Actual mounting is delegated to 'nasreco' function (installed via stow dotfiles).
#
# SECURITY NOTICE:
# - Passwords are stored ONLY in macOS Keychain (AES-256-GCM encryption)
# - Passwords are NEVER written to TOML files, logs, or temporary files
# - nasreco retrieves credentials from Keychain at mount time
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
DEFAULT_MOUNT_BASE="$HOME/NAS"
DEFAULT_WAIT_TIMEOUT=60

# ============================================================================
# Helper Functions
# ============================================================================

# Check if nasreco is available (requires stow dotfiles to be installed)
check_nasreco_available() {
  # Use MAC_SETUP_RUNNING to prevent .zshrc from running fastfetch
  if MAC_SETUP_RUNNING=1 /bin/zsh -i -c 'type nasreco &>/dev/null' 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Get password from macOS Keychain
get_keychain_password() {
  local service="$1"
  security find-generic-password -w -s "$service" 2>/dev/null || echo ""
}

# Store password in macOS Keychain (format compatible with nasreco)
store_keychain_password() {
  local server="$1"
  local username="$2"
  local password="$3"

  local service="${KEYCHAIN_SERVICE_PREFIX}-${server}"

  # Delete existing entry if present (to update)
  security delete-generic-password -s "$service" 2>/dev/null || true

  # Add new entry (nasreco uses -s service only, not -a account)
  local error_output
  if ! error_output=$(security add-generic-password \
    -s "$service" \
    -l "NAS SMB mount for $server" \
    -w "$password" \
    -U 2>&1); then
    log_error "Failed to store password in Keychain: $error_output"
    log_error "Service name: $service"
    return 1
  fi

  log_verbose "Credentials stored in Keychain: $service"
  return 0
}

# List available shares on SMB server (for interactive selection)
list_smb_shares() {
  local server="$1"
  local username="$2"
  local password="$3"

  log_step "Découverte des partages disponibles sur $server..." >&2

  # Remove smb:// prefix if present
  server="${server#smb://}"
  server="${server#//}"

  # Verify server is reachable
  if ! ping -c 1 -W 2 "$server" &>/dev/null; then
    log_error "Serveur inaccessible: $server" >&2
    return 1
  fi

  # URL-encode password
  local encoded_password
  if command_exists perl; then
    encoded_password=$(perl -MURI::Escape -e 'print uri_escape($ARGV[0]);' "$password")
  else
    encoded_password="$password"
  fi

  # List shares using smbutil
  local smbutil_output
  if [[ -n "$password" ]]; then
    smbutil_output=$(smbutil view "//${username}:${encoded_password}@${server}" 2>&1)
  else
    smbutil_output=$(smbutil view "//${server}" 2>&1)
  fi

  if [[ $? -ne 0 ]]; then
    log_error "Impossible de se connecter au serveur SMB: $server" >&2
    return 1
  fi

  # Extract share names
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

  if ! command_exists fzf; then
    log_error "fzf n'est pas installé (requis pour la sélection interactive)" >&2
    return 1
  fi

  local available_shares
  if ! available_shares=$(list_smb_shares "$server" "$username" "$password" 2>&2); then
    return 1
  fi

  local share_count
  share_count=$(echo "$available_shares" | wc -l | xargs)
  log_success "$share_count partages découverts" >&2

  echo "" >&2
  log_info "Partages disponibles sur $server :" >&2
  echo "$available_shares" | sed 's/^/  - /' >&2
  echo "" >&2

  local selected
  selected=$(echo "$available_shares" | fzf \
    --multi \
    --height=60% \
    --border \
    --prompt="Sélectionnez les partages (TAB pour sélectionner, ENTER pour confirmer): " \
    --header="$share_count partages disponibles sur $server" \
    --preview="echo 'Sera monté dans: ~/NAS/{}'" \
    --preview-window=down:3:wrap)

  if [[ -z "$selected" ]]; then
    log_warning "Aucun partage sélectionné" >&2
    return 1
  fi

  echo "$selected"
}

# Create LaunchAgent that calls nasreco
create_launchagent() {
  log_step "Création du LaunchAgent..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create: $LAUNCHAGENT_PLIST"
    return 0
  fi

  mkdir -p "$HOME/Library/LaunchAgents"

  cat > "$LAUNCHAGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCHAGENT_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-c</string>
    <string>source ~/.zshrc && nasreco --quiet</string>
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

# Install and load LaunchAgent
install_launchagent() {
  log_step "Installation du LaunchAgent..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would load: $LAUNCHAGENT_PLIST"
    return 0
  fi

  # Unload if already loaded
  if launchctl list 2>/dev/null | grep -q "$LAUNCHAGENT_LABEL"; then
    log_verbose "Déchargement de l'ancien LaunchAgent..."
    launchctl unload "$LAUNCHAGENT_PLIST" 2>/dev/null || true
  fi

  # Load new LaunchAgent
  if launchctl load "$LAUNCHAGENT_PLIST" 2>/dev/null; then
    log_success "LaunchAgent installé et activé"
    return 0
  else
    log_error "Échec du chargement du LaunchAgent"
    return 1
  fi
}

# Setup sleepwatcher for wake reconnection
setup_sleepwatcher() {
  log_step "Configuration de sleepwatcher (reconnexion au réveil)..."

  # Check if sleepwatcher is installed
  if ! command_exists sleepwatcher; then
    log_info "sleepwatcher n'est pas installé"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would prompt to install sleepwatcher"
      return 0
    fi

    read -r -p "Voulez-vous installer sleepwatcher pour la reconnexion automatique au réveil ? (O/n): " install_sw

    if [[ -z "$install_sw" ]] || [[ "$install_sw" =~ ^[oOyY]$ ]]; then
      log_info "Installation de sleepwatcher..."
      brew install sleepwatcher
      brew services start sleepwatcher
      log_success "sleepwatcher installé"
    else
      log_info "sleepwatcher non installé - les partages ne seront pas reconnectés au réveil"
      return 0
    fi
  else
    log_verbose "sleepwatcher déjà installé"
  fi

  # Create wakeup script
  local wakeup_script="$HOME/.wakeup"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create: $wakeup_script"
    return 0
  fi

  cat > "$wakeup_script" << 'EOF'
#!/bin/bash
# Reconnect NAS shares after wake from sleep
sleep 3
if ping -c 1 -W 2 "${NAS_SERVER:-192.168.1.2}" &>/dev/null; then
    /bin/zsh -c 'source ~/.zshrc && nasreco --quiet' &>/dev/null
fi
EOF

  chmod +x "$wakeup_script"
  log_success "Script de réveil créé: $wakeup_script"

  # Start sleepwatcher if not running
  if ! pgrep -q sleepwatcher; then
    brew services start sleepwatcher 2>/dev/null || true
  fi

  log_success "sleepwatcher configuré pour la reconnexion au réveil"
}

# Update TOML configuration with NAS settings
update_toml_config() {
  local server="$1"
  local username="$2"
  local shares="$3"

  log_step "Mise à jour de la configuration TOML..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would update $TOML_CONFIG with NAS configuration"
    return 0
  fi

  # Check if section already exists
  if grep -q "\[automations.nas-shares\]" "$TOML_CONFIG" 2>/dev/null; then
    log_warning "Section [automations.nas-shares] existe déjà"
    return 0
  fi

  # Convert shares to TOML array
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

  # Append to TOML
  cat >> "$TOML_CONFIG" << EOF

# -----------------------------------------------------------------------------
# NAS Auto-Mount Configuration
# Mounting handled by nasreco (from stow dotfiles)
# -----------------------------------------------------------------------------
[automations.nas-shares]
enabled = true
server = "$server"
username = "$username"
mount_base = "$DEFAULT_MOUNT_BASE"
shares = $shares_array
EOF

  log_success "Configuration TOML mise à jour"
}

# Read NAS configuration from TOML
read_nas_config() {
  local config_server config_username

  config_server=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.server" 2>/dev/null || echo "")
  config_username=$(parse_toml_value "$TOML_CONFIG" "automations.nas-shares.username" 2>/dev/null || echo "")

  # Strip quotes
  config_server="${config_server//\"/}"
  config_username="${config_username//\"/}"

  echo "$config_server|$config_username"
}

# Test mount using nasreco
test_mount() {
  log_subsection "Test du montage NAS"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would run: nasreco --verbose"
    return 0
  fi

  if ! check_nasreco_available; then
    log_error "nasreco n'est pas disponible"
    log_info "Assurez-vous que les dotfiles stow sont installés"
    return 1
  fi

  # Call nasreco (MAC_SETUP_RUNNING prevents fastfetch in .zshrc)
  if MAC_SETUP_RUNNING=1 /bin/zsh -i -c 'nasreco --verbose'; then
    log_success "Partages montés avec succès"
    return 0
  else
    log_error "Échec du montage"
    return 1
  fi
}

# ============================================================================
# Interactive Setup
# ============================================================================
do_interactive_setup() {
  local existing_server="${1:-}"
  local existing_username="${2:-}"

  log_subsection "Configuration interactive du montage NAS"

  # Verify nasreco is available
  if ! check_nasreco_available; then
    log_error "nasreco n'est pas disponible"
    log_info "Les dotfiles stow doivent être installés avant de configurer le NAS"
    log_info "Exécutez d'abord: ./setup.sh --module stow-dotfiles"
    return 1
  fi

  log_success "nasreco disponible (dotfiles installés)"

  # Step 1: Get NAS server
  log_step "Configuration du serveur NAS"
  echo ""

  local nas_server
  if [[ -n "$existing_server" ]]; then
    read -r -p "Adresse du serveur NAS [$existing_server]: " nas_server
    nas_server="${nas_server:-$existing_server}"
  else
    read -r -p "Adresse du serveur NAS (ex: 192.168.1.100, nas.local): " nas_server
  fi

  if [[ -z "$nas_server" ]]; then
    log_error "Serveur NAS requis"
    return 1
  fi

  nas_server="${nas_server#smb://}"
  nas_server="${nas_server#//}"
  log_success "Serveur: $nas_server"

  # Step 2: Get credentials
  log_step "Configuration des identifiants"
  echo ""

  local nas_username
  if [[ -n "$existing_username" ]]; then
    read -r -p "Nom d'utilisateur NAS [$existing_username]: " nas_username
    nas_username="${nas_username:-$existing_username}"
  else
    read -r -p "Nom d'utilisateur NAS: " nas_username
  fi

  if [[ -z "$nas_username" ]]; then
    log_error "Nom d'utilisateur requis"
    return 1
  fi

  local nas_password
  read -r -s -p "Mot de passe NAS: " nas_password
  echo ""

  if [[ -z "$nas_password" ]]; then
    log_error "Mot de passe requis"
    return 1
  fi

  log_success "Identifiants configurés"

  # Step 3: Select shares
  local selected_shares
  selected_shares=$(select_shares_interactive "$nas_server" "$nas_username" "$nas_password")

  if [[ -z "$selected_shares" ]]; then
    log_error "Aucun partage sélectionné"
    return 1
  fi

  # Step 4: Store credentials in Keychain
  log_step "Stockage des identifiants dans le Keychain..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would store credentials in Keychain"
  else
    if store_keychain_password "$nas_server" "$nas_username" "$nas_password"; then
      log_success "Identifiants stockés dans le Keychain"
    else
      log_error "Échec du stockage des identifiants"
      log_info "Essayez manuellement: security add-generic-password -s 'nas-share-$nas_server' -w 'VOTRE_MOT_DE_PASSE'"
      return 1
    fi
  fi

  # Step 5: Update TOML
  update_toml_config "$nas_server" "$nas_username" "$selected_shares"

  # Step 6: Create and install LaunchAgent
  create_launchagent
  install_launchagent

  # Step 7: Setup sleepwatcher
  echo ""
  setup_sleepwatcher

  # Step 8: Offer to test mount
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  Configuration terminée !"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -r -p "Voulez-vous monter les partages maintenant ? (O/n): " do_mount

    if [[ -z "$do_mount" ]] || [[ "$do_mount" =~ ^[oOyY]$ ]]; then
      echo ""
      test_mount
    else
      log_info "Les partages seront montés automatiquement au prochain login"
    fi
  fi

  return 0
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_nas_automount() {
  log_section "Configuration du montage automatique NAS"

  # Check if running with --mount-only flag (legacy support)
  for arg in "$@"; do
    if [[ "$arg" == "--mount-only" ]]; then
      # Just call nasreco
      if check_nasreco_available; then
        MAC_SETUP_RUNNING=1 /bin/zsh -i -c 'nasreco --quiet'
        return $?
      else
        log_error "nasreco non disponible"
        return 1
      fi
    fi
  done

  # Check if already configured
  local config
  config=$(read_nas_config)

  IFS='|' read -r server username <<< "$config"

  if [[ -n "$server" ]] && [[ -n "$username" ]]; then
    # Configuration exists
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "Configuration NAS détectée (mode dry-run)"
      log_success "Serveur: $server"
      log_success "Utilisateur: $username"
      return 0
    fi

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  Configuration NAS détectée"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_success "Serveur: $server"
    log_success "Utilisateur: $username"
    echo ""

    if command_exists fzf; then
      local options=(
        "1|Réutiliser la configuration|Monte les partages avec nasreco"
        "2|Reconfigurer|Redemande serveur, credentials et partages"
        "3|Annuler|Ignore la configuration NAS"
      )

      local choice
      choice=$(printf '%s\n' "${options[@]}" | fzf \
        --height=40% \
        --border=rounded \
        --prompt="Que voulez-vous faire ? " \
        --delimiter="|" \
        --with-nth=2 \
        --preview='echo {3}' \
        --preview-window=down:2:wrap | cut -d'|' -f1)

      case "$choice" in
        1)
          # Ensure LaunchAgent exists
          if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
            create_launchagent
            install_launchagent
          fi
          # Test mount
          echo ""
          read -r -p "Voulez-vous tester le montage maintenant ? (O/n): " do_test
          if [[ -z "$do_test" ]] || [[ "$do_test" =~ ^[oOyY]$ ]]; then
            test_mount
          fi
          ;;
        2)
          do_interactive_setup "$server" "$username"
          ;;
        3|"")
          log_info "Configuration ignorée"
          ;;
      esac
    else
      # No fzf, simple prompt
      read -r -p "Voulez-vous reconfigurer ? (o/N): " reconfig
      if [[ "$reconfig" =~ ^[oOyY]$ ]]; then
        do_interactive_setup "$server" "$username"
      else
        # Ensure LaunchAgent exists
        if [[ ! -f "$LAUNCHAGENT_PLIST" ]]; then
          create_launchagent
          install_launchagent
        fi
        test_mount
      fi
    fi
  else
    # First time setup
    do_interactive_setup
  fi

  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_nas_automount "$@"
fi
