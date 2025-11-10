#!/usr/bin/env bash

# ============================================================================
# Automatisations Module
# Dynamically loads and executes automation scripts
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
# Helper Functions
# ============================================================================

# Check if automations are enabled in TOML config
is_automations_enabled() {
  local enabled
  enabled=$(parse_toml_value "$TOML_CONFIG" "automations.enabled")

  # Default to true if not specified
  if [[ -z "$enabled" ]]; then
    echo "true"
  else
    echo "$enabled"
  fi
}

# Check if a specific automation is enabled in TOML config
is_automation_enabled() {
  local automation_name="$1"
  local enabled
  enabled=$(parse_toml_value "$TOML_CONFIG" "automations.$automation_name")

  # Default to true if not specified (opt-out approach)
  if [[ -z "$enabled" ]]; then
    echo "true"
  else
    echo "$enabled"
  fi
}

# Extract automation name from file path
# Example: /path/to/backup-databases.sh -> backup-databases
get_automation_name() {
  local file_path="$1"
  local basename
  basename=$(basename "$file_path" .sh)
  echo "$basename"
}

# Convert kebab-case to snake_case for function names
# Example: backup-databases -> backup_databases
kebab_to_snake() {
  local kebab="$1"
  echo "$kebab" | tr '-' '_'
}

# Execute a single automation script
run_automation() {
  local script_path="$1"
  local automation_name
  local function_name
  local display_name

  automation_name=$(get_automation_name "$script_path")
  function_name="automation_$(kebab_to_snake "$automation_name")"
  display_name=$(echo "$automation_name" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++)sub(/./,toupper(substr($i,1,1)),$i)}1')

  log_section "Automatisation: $display_name"

  # Check if this specific automation is enabled
  if [[ "$(is_automation_enabled "$automation_name")" != "true" ]]; then
    log_warning "Automatisation désactivée dans la configuration: $automation_name"
    return 0
  fi

  # Source the script
  if ! source "$script_path"; then
    log_error "Impossible de charger le script: $script_path"
    return 1
  fi

  # Check if the expected function exists
  if ! declare -f "$function_name" > /dev/null; then
    log_error "Fonction '$function_name' introuvable dans $script_path"
    log_info "Convention attendue: automation_$(kebab_to_snake "$automation_name")"
    return 1
  fi

  # Execute the automation function
  log_info "Exécution de: $function_name"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: $function_name"
  fi

  # Run the automation and capture the result
  local result=0
  if "$function_name"; then
    log_success "✓ Automatisation '$automation_name' terminée avec succès"
    return 0
  else
    result=$?
    log_error "✗ Automatisation '$automation_name' a échoué (code: $result)"
    return $result
  fi
}

# Ask user if they want to continue after an error
ask_continue_after_error() {
  local automation_name="$1"

  echo
  log_warning "L'automatisation '$automation_name' a échoué."

  # In non-interactive mode or dry-run, continue automatically
  if [[ "$NON_INTERACTIVE" == "true" ]] || [[ "$DRY_RUN" == "true" ]]; then
    log_info "Mode non-interactif: continuation automatique"
    return 0
  fi

  while true; do
    read -r -p "$(tput setaf 3)Voulez-vous continuer avec les autres automatisations ? (o/n): $(tput sgr0)" answer
    case "$answer" in
      [Oo]|[Oo][Uu][Ii])
        log_info "Continuation avec les automatisations restantes..."
        return 0
        ;;
      [Nn]|[Nn][Oo][Nn])
        log_info "Arrêt des automatisations"
        return 1
        ;;
      *)
        echo "Réponse invalide. Veuillez entrer 'o' (oui) ou 'n' (non)."
        ;;
    esac
  done
}

# ============================================================================
# Main Module Function
# ============================================================================
module_automatisations() {
  local automations_dir="$PROJECT_ROOT/automatisations"
  local automation_scripts=()
  local total_count=0
  local success_count=0
  local skipped_count=0
  local failed_count=0

  log_section "Automatisations personnalisées"

  # Check if automations are globally enabled
  if [[ "$(is_automations_enabled)" != "true" ]]; then
    log_warning "Les automatisations sont désactivées dans la configuration"
    log_info "Pour activer : définissez 'enabled = true' dans [automations] de mac-setup.toml"
    return 0
  fi

  # Check if the automations directory exists
  if [[ ! -d "$automations_dir" ]]; then
    log_warning "Le dossier 'automatisations' n'existe pas"
    log_info "Créez le dossier et ajoutez vos scripts : mkdir -p '$automations_dir'"
    return 0
  fi

  # Discover automation scripts (*.sh files, excluding templates)
  while IFS= read -r -d '' script; do
    automation_scripts+=("$script")
  done < <(find "$automations_dir" -maxdepth 1 -name "*.sh" ! -name "*.template" -type f -print0 | sort -z)

  # Check if any automation scripts were found
  if [[ ${#automation_scripts[@]} -eq 0 ]]; then
    log_info "Aucun script d'automatisation trouvé dans '$automations_dir'"
    log_info "Consultez '$automations_dir/README.md' pour créer vos automatisations"
    return 0
  fi

  total_count=${#automation_scripts[@]}
  log_info "Scripts d'automatisation découverts: $total_count"
  echo

  # Execute each automation script in alphabetical order
  for script in "${automation_scripts[@]}"; do
    local automation_name
    automation_name=$(get_automation_name "$script")

    # Check if this automation should be skipped
    if [[ "$(is_automation_enabled "$automation_name")" != "true" ]]; then
      log_step "Automatisation désactivée: $automation_name"
      ((skipped_count++))
      continue
    fi

    # Execute the automation
    if run_automation "$script"; then
      ((success_count++))
    else
      ((failed_count++))

      # Ask user if they want to continue
      if ! ask_continue_after_error "$automation_name"; then
        log_warning "Arrêt des automatisations à la demande de l'utilisateur"
        break
      fi
    fi

    echo
  done

  # Display summary
  log_section "Résumé des automatisations"
  log_info "Total: $total_count"
  log_success "Réussies: $success_count"

  if [[ $skipped_count -gt 0 ]]; then
    log_warning "Ignorées: $skipped_count"
  fi

  if [[ $failed_count -gt 0 ]]; then
    log_error "Échouées: $failed_count"
  fi

  # Return success if at least one automation succeeded or all were skipped
  if [[ $failed_count -eq 0 ]] || [[ $success_count -gt 0 ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_automatisations
fi
