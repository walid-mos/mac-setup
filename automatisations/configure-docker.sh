#!/usr/bin/env bash

# ============================================================================
# Docker/Colima Configuration Automation
# Configures Colima with optimal settings for development
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
# Helper Functions
# ============================================================================

is_colima_running() {
  colima status &>/dev/null && return 0 || return 1
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_configure_docker() {
  log_subsection "Configuration de Docker/Colima"

  # Check if colima is installed
  if ! command_exists colima; then
    log_warning "colima n'est pas installé"
    log_info "colima devrait être installé via Homebrew (section docker)"
    return 0  # Not an error, just skip
  fi

  log_success "colima est installé"

  # Check if docker is installed
  if ! command_exists docker; then
    log_warning "docker n'est pas installé"
    log_info "docker devrait être installé via Homebrew (section docker)"
    return 0  # Not an error, just skip
  fi

  log_success "docker est installé"

  # Check current colima status
  if is_colima_running; then
    log_info "colima est déjà en cours d'exécution"
    log_step "Affichage de la configuration actuelle..."

    if [[ "$DRY_RUN" != "true" ]]; then
      colima status
    fi

    log_warning "Pour reconfigurer, arrêtez colima manuellement: colima stop && colima delete"
    return 0
  fi

  # Start colima with configured resources
  log_step "Démarrage de colima avec la configuration personnalisée..."
  log_info "CPU: $COLIMA_CPU cores"
  log_info "Mémoire: ${COLIMA_MEMORY}GB"
  log_info "Disque: ${COLIMA_DISK}GB"
  log_info "Architecture: $COLIMA_ARCH"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: colima start --cpu $COLIMA_CPU --memory $COLIMA_MEMORY --disk $COLIMA_DISK --arch $COLIMA_ARCH"
  else
    if colima start \
      --cpu "$COLIMA_CPU" \
      --memory "$COLIMA_MEMORY" \
      --disk "$COLIMA_DISK" \
      --arch "$COLIMA_ARCH"; then
      log_success "colima démarré avec succès"
    else
      log_error "Échec du démarrage de colima"
      return 1
    fi
  fi

  # Verify docker is working
  if [[ "$DRY_RUN" != "true" ]]; then
    log_step "Vérification de Docker..."

    if docker info &>/dev/null; then
      log_success "Docker fonctionne correctement"

      # Display docker info
      local docker_version
      docker_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
      log_info "Version Docker: $docker_version"
    else
      log_error "Docker ne répond pas correctement"
      return 1
    fi
  fi

  # Display colima status
  if [[ "$DRY_RUN" != "true" ]]; then
    log_step "État de colima:"
    colima status
  fi

  log_success "Configuration Docker/Colima terminée"
  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_configure_docker
fi
