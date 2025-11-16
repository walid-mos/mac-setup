#!/usr/bin/env bash

# ============================================================================
# React Native iOS Environment Setup
# Configures complete React Native development environment for iOS
# Includes: Ruby, CocoaPods, Xcode verification, Node.js, Watchman
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
# Configuration
# ============================================================================
REQUIRED_NODE_VERSION="20.19.4"
REQUIRED_RUBY_VERSION="3.0"  # Minimum version for CocoaPods

# ============================================================================
# Helper Functions
# ============================================================================

# Check if Xcode app is installed (not just CLI tools)
check_xcode_installation() {
  if [[ -d "/Applications/Xcode.app" ]]; then
    return 0
  else
    return 1
  fi
}

# Check if iOS Simulator is available
check_ios_simulator() {
  if command_exists xcrun; then
    local simulator_count
    simulator_count=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone" || echo "0")

    if [[ "$simulator_count" -gt 0 ]]; then
      return 0
    fi
  fi
  return 1
}

# Verify Node.js version meets minimum requirement
verify_node_version() {
  local current_version="$1"
  local required_version="$2"

  # Remove 'v' prefix if present
  current_version="${current_version#v}"
  required_version="${required_version#v}"

  # Compare versions (simple numerical comparison for major.minor.patch)
  if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]; then
    return 0
  else
    return 1
  fi
}

# Check Ruby version meets minimum requirement
verify_ruby_version() {
  local current_version="$1"
  local required_version="$2"

  # Extract major.minor version
  local current_major_minor
  current_major_minor=$(echo "$current_version" | grep -oE '^[0-9]+\.[0-9]+')

  if [[ "$(printf '%s\n' "$required_version" "$current_major_minor" | sort -V | head -n1)" == "$required_version" ]]; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_react_native_ios() {
  log_subsection "Configuration de l'environnement React Native iOS"

  # ----------------------------------
  # Step 0: Verify Homebrew Ruby installation
  # ----------------------------------
  log_step "Vérification de l'installation Homebrew Ruby..."

  local homebrew_ruby_bin="/opt/homebrew/opt/ruby/bin/ruby"

  # Check if Homebrew Ruby binary exists
  if [[ ! -f "$homebrew_ruby_bin" ]]; then
    log_error "Homebrew Ruby n'est pas installé"
    log_info "Ajoutez 'ruby' dans [brew.packages.languages] du fichier mac-setup.toml"
    log_info "Puis réexécutez: ./setup.sh --module brew-packages"
    return 1
  fi

  log_success "Binaire Homebrew Ruby trouvé: $homebrew_ruby_bin"

  # Prepend Homebrew Ruby to PATH for this script execution
  # This ensures we use Ruby 3.x from Homebrew, not system Ruby 2.6.x
  export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
  export PATH="/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"

  # Verify that 'which ruby' now points to Homebrew Ruby
  local active_ruby
  active_ruby=$(which ruby)

  if [[ "$active_ruby" != "$homebrew_ruby_bin" ]]; then
    log_error "Ruby PATH incorrect"
    log_info "Attendu: $homebrew_ruby_bin"
    log_info "Actuel: $active_ruby"
    log_info "Le PATH n'a pas été correctement configuré"
    return 1
  fi

  log_success "Ruby PATH correct: $active_ruby"

  # ----------------------------------
  # Step 1: Verify macOS
  # ----------------------------------
  log_step "Vérification du système d'exploitation..."

  if [[ "$(uname -s)" != "Darwin" ]]; then
    log_error "Ce script nécessite macOS"
    return 1
  fi

  log_success "macOS détecté"

  # ----------------------------------
  # Step 2: Verify Ruby version
  # ----------------------------------
  log_step "Vérification de la version Ruby..."

  local ruby_version
  ruby_version=$(ruby --version | awk '{print $2}')

  if verify_ruby_version "$ruby_version" "$REQUIRED_RUBY_VERSION"; then
    log_success "Ruby $ruby_version installé (>= $REQUIRED_RUBY_VERSION requis)"
  else
    log_error "Ruby $ruby_version est trop ancien (>= $REQUIRED_RUBY_VERSION requis)"
    log_info "Homebrew Ruby devrait être >= 3.4. Essayez: brew upgrade ruby"
    return 1
  fi

  # ----------------------------------
  # Step 3: Verify/Install CocoaPods
  # ----------------------------------
  log_step "Vérification de CocoaPods..."

  # Ensure user-installed gems are in PATH
  local ruby_version
  ruby_version="$(ruby -e 'puts RUBY_VERSION.split(".")[0,2].join(".") + ".0"')"
  export PATH="$HOME/.gem/ruby/${ruby_version}/bin:$PATH"

  if command_exists pod; then
    local pod_version
    pod_version=$(pod --version 2>/dev/null || echo "unknown")
    log_success "CocoaPods $pod_version déjà installé"
  else
    log_info "Installation de CocoaPods..."

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would execute: gem install cocoapods"
    else
      if gem install cocoapods --user-install; then
        log_success "CocoaPods installé avec succès"
      else
        log_error "Échec de l'installation de CocoaPods"
        log_info "Essayez manuellement: gem install cocoapods --user-install"
        return 1
      fi
    fi
  fi

  # ----------------------------------
  # Step 4: Run pod setup (initialize specs repo)
  # ----------------------------------
  log_step "Initialisation du repository CocoaPods specs..."

  local pod_repo_dir="$HOME/.cocoapods/repos"

  if [[ -d "$pod_repo_dir/trunk" ]] || [[ -d "$pod_repo_dir/master" ]]; then
    log_success "Repository CocoaPods déjà initialisé"
  else
    log_info "Téléchargement du repository specs (~600MB, peut prendre 10-15 min)..."

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would execute: pod setup"
    else
      # Verify pod command is available
      if ! command_exists pod; then
        log_error "Commande 'pod' non trouvée dans PATH"
        log_info "PATH actuel: $PATH"
        log_info "Essayez de relancer votre shell: exec zsh"
        return 1
      fi

      log_warning "Cette opération peut être longue, merci de patienter..."

      if pod setup; then
        log_success "Repository CocoaPods initialisé"
      else
        log_error "Échec de l'initialisation CocoaPods"
        log_info "Vous pouvez réessayer manuellement: pod setup"
        return 1
      fi
    fi
  fi

  # ----------------------------------
  # Step 5: Verify Xcode installation
  # ----------------------------------
  log_step "Vérification de Xcode..."

  if check_xcode_installation; then
    local xcode_version
    xcode_version=$(xcodebuild -version 2>/dev/null | head -n1 || echo "Version inconnue")
    log_success "Xcode installé: $xcode_version"

    # Check Xcode Command Line Tools
    log_step "Vérification des Xcode Command Line Tools..."

    if xcode-select -p &>/dev/null; then
      local xcode_path
      xcode_path=$(xcode-select -p)
      log_success "Command Line Tools actifs: $xcode_path"
    else
      log_warning "Command Line Tools non configurés"
      log_info "Exécutez: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    fi
  else
    log_warning "Xcode n'est pas installé"
    log_info ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  Pour développer en React Native iOS, vous devez:"
    log_info "  1. Ouvrir l'App Store"
    log_info "  2. Rechercher 'Xcode'"
    log_info "  3. Installer Xcode (12-15 GB)"
    log_info "  4. Ouvrir Xcode et accepter la licence"
    log_info "  5. Installer les simulateurs iOS:"
    log_info "     Xcode > Settings > Platforms"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info ""

    # Don't fail - allow continuation for other checks
  fi

  # ----------------------------------
  # Step 6: Verify fnm and Node.js
  # ----------------------------------
  log_step "Vérification de Node.js via fnm..."

  if ! command_exists fnm; then
    log_error "fnm n'est pas installé"
    log_info "fnm devrait être installé via le module curl-tools"
    return 1
  fi

  # Source fnm environment
  if [[ -f "$HOME/.local/share/fnm/env" ]]; then
    source "$HOME/.local/share/fnm/env"
  elif [[ -f "$HOME/.fnm/env" ]]; then
    source "$HOME/.fnm/env"
  fi

  if ! command_exists node; then
    log_error "Node.js n'est pas installé"
    log_info "Installez Node.js avec: fnm install $REQUIRED_NODE_VERSION"
    return 1
  fi

  local node_version
  node_version=$(node --version)

  if verify_node_version "$node_version" "$REQUIRED_NODE_VERSION"; then
    log_success "Node.js $node_version installé (>= $REQUIRED_NODE_VERSION requis)"
  else
    log_warning "Node.js $node_version est plus ancien que la version recommandée $REQUIRED_NODE_VERSION"
    log_info "Installez une version plus récente: fnm install $REQUIRED_NODE_VERSION && fnm default $REQUIRED_NODE_VERSION"
  fi

  # ----------------------------------
  # Step 7: Verify Watchman
  # ----------------------------------
  log_step "Vérification de Watchman..."

  if command_exists watchman; then
    local watchman_version
    watchman_version=$(watchman --version 2>/dev/null || echo "unknown")
    log_success "Watchman $watchman_version installé"
  else
    log_warning "Watchman n'est pas installé (fortement recommandé par React Native)"
    log_info "Installez avec: brew install watchman"
    log_info "Ou ajoutez 'watchman' dans [brew.packages] du fichier mac-setup.toml"
  fi

  # ----------------------------------
  # Step 8: Configure shell environment
  # ----------------------------------
  log_step "Configuration de l'environnement shell..."

  local zshenv_file="$HOME/.zshenv"
  local fnm_init_line='eval "$(fnm env --use-on-cd --shell zsh)"'

  if [[ -f "$zshenv_file" ]] && grep -q "fnm env" "$zshenv_file"; then
    log_success "~/.zshenv contient déjà la configuration fnm"
  else
    log_info "Ajout de l'initialisation fnm à ~/.zshenv (requis pour Xcode)"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would add fnm initialization to ~/.zshenv"
    else
      # Create .zshenv if it doesn't exist
      touch "$zshenv_file"

      # Add fnm initialization
      {
        echo ""
        echo "# fnm initialization (for Xcode compatibility)"
        echo "$fnm_init_line"
      } >> "$zshenv_file"

      log_success "Configuration ajoutée à ~/.zshenv"
      log_info "La configuration sera active au prochain démarrage de shell"
    fi
  fi

  # ----------------------------------
  # Step 9: Create .xcode.env template
  # ----------------------------------
  log_step "Création du template .xcode.env..."

  local xcode_env_template="$HOME/.xcode.env.template"

  if [[ -f "$xcode_env_template" ]]; then
    log_success "Template .xcode.env existe déjà"
  else
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "[DRY RUN] Would create .xcode.env template at $xcode_env_template"
    else
      cat > "$xcode_env_template" << 'EOF'
# .xcode.env
# This file is used by Xcode to locate Node.js for React Native builds
# Copy this file to the root of your React Native project as ".xcode.env"

# Specify the path to your Node.js binary
# Option 1: Using fnm (recommended)
export NODE_BINARY=$(command -v node)

# Option 2: Using absolute path
# export NODE_BINARY="$HOME/.local/share/fnm/node-versions/v20.19.4/installation/bin/node"

# Option 3: Using nvm
# export NODE_BINARY="$HOME/.nvm/versions/node/v20.19.4/bin/node"
EOF

      log_success "Template créé: $xcode_env_template"
      log_info "Copiez ce fichier dans vos projets React Native comme '.xcode.env'"
    fi
  fi

  # ----------------------------------
  # Step 10: Check iOS Simulators
  # ----------------------------------
  log_step "Vérification des simulateurs iOS..."

  if check_ios_simulator; then
    local simulator_count
    simulator_count=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone" || echo "0")
    log_success "$simulator_count simulateurs iOS disponibles"
  else
    log_warning "Aucun simulateur iOS détecté"
    log_info "Installez des simulateurs via: Xcode > Settings > Platforms"
  fi

  # ----------------------------------
  # Step 11: Verification summary
  # ----------------------------------
  log_step "Résumé de la vérification..."

  if [[ "$DRY_RUN" != "true" ]]; then
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  État de l'environnement React Native iOS"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Ruby
    if command_exists ruby; then
      log_info "  ✅ Ruby: $(ruby --version | awk '{print $2}')"
    else
      log_info "  ❌ Ruby: Non installé"
    fi

    # CocoaPods
    if command_exists pod; then
      log_info "  ✅ CocoaPods: $(pod --version 2>/dev/null || echo 'unknown')"
    else
      log_info "  ❌ CocoaPods: Non installé"
    fi

    # Xcode
    if check_xcode_installation; then
      log_info "  ✅ Xcode: $(xcodebuild -version 2>/dev/null | head -n1 | awk '{print $2}')"
    else
      log_info "  ⚠️  Xcode: Non installé (requis pour iOS)"
    fi

    # Node.js
    if command_exists node; then
      log_info "  ✅ Node.js: $(node --version)"
    else
      log_info "  ❌ Node.js: Non installé"
    fi

    # Watchman
    if command_exists watchman; then
      log_info "  ✅ Watchman: $(watchman --version 2>/dev/null || echo 'unknown')"
    else
      log_info "  ⚠️  Watchman: Non installé (recommandé)"
    fi

    # iOS Simulators
    if check_ios_simulator; then
      local sim_count
      sim_count=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone" || echo "0")
      log_info "  ✅ Simulateurs iOS: $sim_count disponibles"
    else
      log_info "  ⚠️  Simulateurs iOS: Aucun détecté"
    fi

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
  fi

  # ----------------------------------
  # Step 12: Next steps
  # ----------------------------------
  log_success "Configuration React Native iOS terminée"
  echo ""
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  Prochaines étapes:"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log_info "  1. Créer un nouveau projet React Native:"
  log_info "     npx react-native@latest init MonProjet"
  log_info ""
  log_info "  2. Copier le template .xcode.env dans votre projet:"
  log_info "     cp ~/.xcode.env.template <project>/.xcode.env"
  log_info ""
  log_info "  3. Installer les dépendances iOS:"
  log_info "     cd <project>/ios && pod install"
  log_info ""
  log_info "  4. Lancer sur simulateur iOS:"
  log_info "     npx react-native run-ios"
  log_info ""
  log_info "  5. Documentation officielle:"
  log_info "     https://reactnative.dev/docs/environment-setup"
  log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_react_native_ios
fi
