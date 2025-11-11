#!/usr/bin/env bash

# ============================================================================
# Extended macOS Defaults Configuration
# Additional system preferences beyond the main macos-defaults module
# ============================================================================

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
fi

# ============================================================================
# Configuration Functions
# ============================================================================

configure_trackpad() {
  log_step "Configuration du trackpad..."

  # Enable tap to click
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would enable tap to click"
  else
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    log_success "Tap to click activé"
  fi

  # Three finger drag
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would enable three finger drag"
  else
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag -bool true
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
    log_success "Three finger drag activé"
  fi
}

configure_screenshots() {
  log_step "Configuration des captures d'écran..."

  local screenshots_dir="$HOME/Pictures/Screenshots"

  # Create screenshots directory
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would create directory: $screenshots_dir"
  else
    mkdir -p "$screenshots_dir"
    log_success "Dossier créé: $screenshots_dir"
  fi

  # Set screenshots location
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would set screenshots location to: $screenshots_dir"
  else
    defaults write com.apple.screencapture location -string "$screenshots_dir"
    log_success "Emplacement des captures: $screenshots_dir"
  fi

  # Disable shadow in screenshots
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable shadow in screenshots"
  else
    defaults write com.apple.screencapture disable-shadow -bool true
    log_success "Ombre dans les captures désactivée"
  fi

  # Set screenshot format to PNG
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would set screenshot format to PNG"
  else
    defaults write com.apple.screencapture type -string "png"
    log_success "Format des captures: PNG"
  fi
}

configure_menubar() {
  log_step "Configuration de la barre de menu..."

  # Show battery percentage
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would show battery percentage"
  else
    defaults write com.apple.menuextra.battery ShowPercent -string "YES"
    log_success "Pourcentage de batterie affiché"
  fi

  # Show date and time
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would configure date/time display"
  else
    defaults write com.apple.menuextra.clock DateFormat -string "EEE d MMM  HH:mm:ss"
    log_success "Format date/heure configuré"
  fi
}

configure_mission_control() {
  log_step "Configuration de Mission Control..."

  # Don't automatically rearrange Spaces based on most recent use
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable automatic Space rearrangement"
  else
    defaults write com.apple.dock mru-spaces -bool false
    log_success "Réorganisation automatique des Spaces désactivée"
  fi

  # Speed up Mission Control animations
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would speed up Mission Control animations"
  else
    defaults write com.apple.dock expose-animation-duration -float 0.1
    log_success "Animations Mission Control accélérées"
  fi
}

configure_keyboard() {
  log_step "Configuration du clavier..."

  # Disable press-and-hold for keys in favor of key repeat
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable press-and-hold"
  else
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    log_success "Press-and-hold désactivé (répétition de touches activée)"
  fi

  # Note: Key repeat rate is already configured in macos-defaults module
}

configure_energy() {
  log_step "Configuration de l'économie d'énergie..."

  # Prevent sleep when display is off (for laptops on power)
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would configure energy settings"
  else
    sudo pmset -c sleep 0
    sudo pmset -c displaysleep 15
    log_success "Paramètres d'énergie configurés (sur secteur)"
  fi
}

configure_security() {
  log_step "Configuration de la sécurité..."

  # Disable Gatekeeper - Allow apps from anywhere
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable Gatekeeper (allow apps from anywhere)"
  else
    log_warning "Désactivation de Gatekeeper (permet l'installation d'apps non vérifiées)"
    if sudo spctl --master-disable 2>/dev/null; then
      log_success "Gatekeeper désactivé - apps de sources non identifiées autorisées"
    else
      log_error "Impossible de désactiver Gatekeeper (nécessite sudo)"
      return 1
    fi
  fi

  # Disable quarantine for downloaded files
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable quarantine for downloaded files"
  else
    defaults write com.apple.LaunchServices LSQuarantine -bool false
    log_success "Quarantaine des fichiers téléchargés désactivée"
  fi

  # Disable the warning when opening apps from unidentified developers
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would disable unidentified developer warning"
  else
    defaults write com.apple.LaunchServices LSQuarantine -bool false
    log_success "Avertissement développeurs non identifiés désactivé"
  fi

  log_info "Note: Ces paramètres réduisent la sécurité mais facilitent le développement"
  log_info "Vous pouvez réactiver Gatekeeper avec: sudo spctl --master-enable"
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_expand_macos_defaults() {
  log_subsection "Configuration macOS étendue"

  # Check if macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    log_error "Ce script est uniquement compatible avec macOS"
    return 1
  fi

  # Apply configurations
  configure_trackpad
  configure_screenshots
  configure_menubar
  configure_mission_control
  configure_keyboard
  configure_energy
  configure_security

  # Restart affected services
  if [[ "$DRY_RUN" != "true" ]]; then
    log_step "Redémarrage des services affectés..."

    killall Dock 2>/dev/null || true
    killall SystemUIServer 2>/dev/null || true

    log_success "Services redémarrés"
  fi

  log_success "Configuration macOS étendue terminée"
  log_info "Certains changements nécessitent une reconnexion ou un redémarrage"

  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_expand_macos_defaults
fi
