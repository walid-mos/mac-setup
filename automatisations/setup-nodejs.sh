#!/usr/bin/env bash

# ============================================================================
# Node.js Setup Automation
# Configures Node.js via fnm with default version from config
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
# Main Automation Function
# ============================================================================
automation_setup_nodejs() {
  log_subsection "Configuration de Node.js via fnm"

  # Check if fnm is installed
  if ! command_exists fnm; then
    log_error "fnm n'est pas installé"
    log_info "fnm devrait être installé via le module curl-tools"
    return 1
  fi

  # Source fnm to make it available in current shell
  log_step "Chargement de fnm dans le shell..."
  if [[ -f "$HOME/.local/share/fnm/env" ]]; then
    source "$HOME/.local/share/fnm/env"
  elif [[ -f "$HOME/.fnm/env" ]]; then
    source "$HOME/.fnm/env"
  else
    log_warning "fnm env file non trouvé, tentative d'utilisation directe"
  fi

  # Verify fnm is now available
  if ! command_exists fnm; then
    log_error "Impossible de charger fnm"
    return 1
  fi

  log_success "fnm est disponible"

  # Install Node.js version from config
  log_step "Installation de Node.js version: $NODEJS_DEFAULT_VERSION"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: fnm install $NODEJS_DEFAULT_VERSION"
  else
    if fnm install "$NODEJS_DEFAULT_VERSION"; then
      log_success "Node.js $NODEJS_DEFAULT_VERSION installé"
    else
      log_error "Échec de l'installation de Node.js"
      return 1
    fi
  fi

  # Set as default version
  log_step "Configuration de la version par défaut..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: fnm default $NODEJS_DEFAULT_VERSION"
  else
    if fnm default "$NODEJS_DEFAULT_VERSION"; then
      log_success "Version par défaut définie: $NODEJS_DEFAULT_VERSION"
    else
      log_error "Échec de la définition de la version par défaut"
      return 1
    fi
  fi

  # Display installed version
  if [[ "$DRY_RUN" != "true" ]]; then
    local node_version
    node_version=$(fnm current 2>/dev/null || echo "unknown")
    log_info "Version Node.js active: $node_version"
  fi

  # Check if pnpm is available (should be installed via curl-tools)
  if command_exists pnpm; then
    log_success "pnpm est disponible"

    if [[ "$DRY_RUN" != "true" ]]; then
      local pnpm_version
      pnpm_version=$(pnpm --version 2>/dev/null || echo "unknown")
      log_info "Version pnpm: $pnpm_version"
    fi
  else
    log_warning "pnpm n'est pas installé (devrait être installé via curl-tools)"
  fi

  log_success "Configuration Node.js terminée"
  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_nodejs
fi
