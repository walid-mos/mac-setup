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
  source "$PROJECT_ROOT/lib/toml-parser.sh"

  # Initialize TOML parser (for standalone execution)
  # Will use dasel if available, fallback to awk otherwise
  init_toml_parser 2>/dev/null || true
fi

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_nodejs() {
  log_subsection "Configuration de Node.js via fnm"

  # Read Node.js version from TOML config (fallback to env var or default)
  local nodejs_version
  nodejs_version=$(parse_toml_value "$TOML_CONFIG" "nodejs.default_version" 2>/dev/null)

  # Fallback to environment variable or default if not set in TOML
  if [[ -z "$nodejs_version" ]]; then
    nodejs_version="${NODEJS_DEFAULT_VERSION:-22}"
  fi

  # Remove quotes if present (TOML parser may include them)
  nodejs_version="${nodejs_version//\'/}"
  nodejs_version="${nodejs_version//\"/}"

  log_info "Version configurée: $nodejs_version"

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
  log_step "Installation de Node.js version: $nodejs_version"

  # Determine install command based on version string
  local install_cmd="fnm install"
  local version_arg="$nodejs_version"

  case "$nodejs_version" in
    "lts")
      install_cmd="fnm install --lts"
      version_arg=""
      ;;
    "latest")
      install_cmd="fnm install --latest"
      version_arg=""
      ;;
    *)
      # Numeric version or specific version string
      install_cmd="fnm install"
      version_arg="$nodejs_version"
      ;;
  esac

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: $install_cmd $version_arg"
  else
    if [[ -n "$version_arg" ]]; then
      if $install_cmd "$version_arg"; then
        log_success "Node.js $nodejs_version installé"
      else
        log_error "Échec de l'installation de Node.js"
        return 1
      fi
    else
      if $install_cmd; then
        log_success "Node.js $nodejs_version installé"
      else
        log_error "Échec de l'installation de Node.js"
        return 1
      fi
    fi
  fi

  # Set as default version
  log_step "Configuration de la version par défaut..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: fnm default $nodejs_version"
  else
    # Use the version we just installed
    if fnm default "$nodejs_version"; then
      log_success "Version par défaut définie: $nodejs_version"
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
