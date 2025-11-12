#!/usr/bin/env bash

# =============================================================================
# Mac Setup Bootstrap Installer
# =============================================================================
# Downloads and executes the mac-setup repository
# Repository: https://github.com/walid-mos/dotfiles
#
# IMPORTANT: This script uses ONLY macOS native tools:
#   - bash, curl, git, uname, command, read, echo
#   - No jq, dasel, brew, or any other tools (not yet installed)
# =============================================================================

set -eo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

REPO_URL="https://github.com/walid-mos/dotfiles.git"
DOTFILES_BRANCH="main"
INSTALL_DIR="/tmp/mac-setup-$$"
SETUP_SCRIPT="${INSTALL_DIR}/mac-setup/setup.sh"

# Colors for output (using tput for maximum compatibility)
if command -v tput &> /dev/null && [[ -t 1 ]]; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  BOLD=$(tput bold)
  NC=$(tput sgr0) # No Color
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  BOLD=''
  NC=''
fi

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

print_error() {
  echo "${RED}Error: $1${NC}" >&2
}

print_success() {
  echo "${GREEN}$1${NC}"
}

print_info() {
  echo "${BLUE}$1${NC}"
}

print_warning() {
  echo "${YELLOW}$1${NC}"
}

check_prerequisites() {
  print_info "Checking prerequisites..."

  # Check if running on macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    print_error "This script only works on macOS"
    echo "Detected OS: $(uname)"
    exit 1
  fi

  # Check bash version (need 3.2+, macOS default is 3.2.57)
  local bash_major="${BASH_VERSINFO[0]}"
  local bash_minor="${BASH_VERSINFO[1]}"

  if [[ "${bash_major}" -lt 3 ]] || [[ "${bash_major}" -eq 3 && "${bash_minor}" -lt 2 ]]; then
    print_error "This script requires bash 3.2 or higher"
    echo "Current bash version: ${BASH_VERSION}"
    exit 1
  fi

  # Check curl (should always be present on macOS, but verify)
  if ! command -v curl &> /dev/null; then
    print_error "curl is not available (unexpected on macOS)"
    exit 1
  fi

  # Check if Xcode Command Line Tools are installed
  if ! xcode-select -p &>/dev/null; then
    print_warning "Xcode Command Line Tools are not installed"
    print_info "Installing Xcode Command Line Tools (required for git)..."
    echo ""

    if [[ "${UNATTENDED}" != "true" ]]; then
      print_info "A dialog will appear to install Command Line Tools (~700MB download)"
      print_info "Please click 'Install' and accept the license agreement"
      echo ""
      printf "%s" "${YELLOW}Press Enter when ready to continue...${NC}"
      read -r
    fi

    # Trigger installation
    xcode-select --install 2>/dev/null || {
      print_warning "xcode-select --install command failed"
      print_info "This may happen if installation is already in progress"
    }

    # Wait for installation to complete
    print_info "Waiting for Xcode Command Line Tools installation to complete..."
    echo ""

    local timeout=600  # 10 minutes timeout
    local elapsed=0
    local check_interval=5

    while ! xcode-select -p &>/dev/null; do
      if [[ ${elapsed} -ge ${timeout} ]]; then
        echo ""
        print_error "Timeout waiting for Xcode Command Line Tools installation"
        echo ""
        echo "Please complete the installation manually and run this installer again:"
        echo "  ${BOLD}xcode-select --install${NC}"
        exit 1
      fi

      sleep ${check_interval}
      ((elapsed += check_interval))

      if [[ $((elapsed % 30)) -eq 0 ]]; then
        print_info "Still waiting... (${elapsed} seconds elapsed)"
      fi
    done

    echo ""
    print_success "Xcode Command Line Tools installed successfully"
  else
    print_success "Xcode Command Line Tools are already installed"
  fi

  # Verify git is now available
  if ! command -v git &> /dev/null; then
    print_error "git not found after Xcode Command Line Tools installation"
    exit 1
  fi

  print_success "Prerequisites check passed"
}

show_summary() {
  cat << EOF

${BLUE}${BOLD}╔═══════════════════════════════════════════════════════════════╗
║                   Mac Setup Installation                      ║
╚═══════════════════════════════════════════════════════════════╝${NC}

This installer will:
  ${BOLD}1.${NC} Clone the dotfiles repository to: ${BOLD}${INSTALL_DIR}${NC} (temporary)
  ${BOLD}2.${NC} Run the automated macOS setup script

The setup script will install:
  ${GREEN}✓${NC} Homebrew and packages (Neovim, fzf, ripgrep, etc.)
  ${GREEN}✓${NC} Applications (VSCode, Ghostty, Raycast, etc.)
  ${GREEN}✓${NC} Oh My Zsh and plugins
  ${GREEN}✓${NC} Development tools (fnm, pnpm, Claude CLI, etc.)
  ${GREEN}✓${NC} Your dotfiles via GNU Stow
  ${GREEN}✓${NC} Git configuration
  ${GREEN}✓${NC} macOS system preferences

${YELLOW}${BOLD}⚠️  This will modify your system configuration${NC}

For more information:
  ${BLUE}https://github.com/walid-mos/dotfiles/tree/main/mac-setup${NC}

EOF
}

confirm_installation() {
  if [[ "${UNATTENDED}" == "true" ]]; then
    print_info "Running in unattended mode, proceeding automatically..."
    return 0
  fi

  echo ""
  while true; do
    # Use printf for maximum compatibility
    printf "%s" "${YELLOW}${BOLD}Do you want to proceed? [y/N]: ${NC}"
    read -r response

    case "$response" in
      [yY][eE][sS]|[yY])
        echo ""
        return 0
        ;;
      [nN][oO]|[nN]|"")
        echo ""
        print_info "Installation cancelled by user"
        exit 0
        ;;
      *)
        print_error "Please answer yes or no"
        ;;
    esac
  done
}

clone_repository() {
  print_info "Cloning repository to ${INSTALL_DIR}..."

  if [[ -d "${INSTALL_DIR}" ]]; then
    print_warning "Directory ${INSTALL_DIR} already exists"

    if [[ -d "${INSTALL_DIR}/.git" ]]; then
      print_info "Updating existing repository..."
      cd "${INSTALL_DIR}" || {
        print_error "Failed to enter directory: ${INSTALL_DIR}"
        exit 1
      }

      git pull origin "${DOTFILES_BRANCH}" || {
        print_error "Failed to update repository"
        echo "You may need to manually resolve conflicts in: ${INSTALL_DIR}"
        exit 1
      }

      print_success "Repository updated successfully"
    else
      print_error "Directory exists but is not a git repository"
      echo ""
      echo "Please remove or rename: ${INSTALL_DIR}"
      echo "Then run this installer again."
      exit 1
    fi
  else
    # Clone repository
    git clone -b "${DOTFILES_BRANCH}" "${REPO_URL}" "${INSTALL_DIR}" || {
      print_error "Failed to clone repository"
      echo ""
      echo "This could be due to:"
      echo "  - Network connectivity issues"
      echo "  - Repository URL changed"
      echo "  - Git authentication required"
      echo "  - Branch '${DOTFILES_BRANCH}' does not exist"
      exit 1
    }

    print_success "Repository cloned successfully"
  fi
}

run_setup() {
  print_info "Running setup script..."
  echo ""

  if [[ ! -f "${SETUP_SCRIPT}" ]]; then
    print_error "Setup script not found at: ${SETUP_SCRIPT}"
    echo "Repository structure may have changed."
    exit 1
  fi

  # Make executable if not already
  if [[ ! -x "${SETUP_SCRIPT}" ]]; then
    chmod +x "${SETUP_SCRIPT}" || {
      print_error "Failed to make setup script executable"
      exit 1
    }
  fi

  # Pass through any additional arguments to setup.sh
  cd "${INSTALL_DIR}/mac-setup" || {
    print_error "Failed to enter mac-setup directory"
    exit 1
  }

  # Execute setup.sh with passed arguments
  "${SETUP_SCRIPT}" "${SETUP_ARGS[@]}"
  local setup_exit_code=$?

  if [[ ${setup_exit_code} -ne 0 ]]; then
    echo ""
    print_error "Setup script failed with exit code: ${setup_exit_code}"
    exit ${setup_exit_code}
  fi
}

show_success_message() {
  cat << EOF

${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════════╗
║           Mac Setup Installation Complete! 🎉                 ║
╚═══════════════════════════════════════════════════════════════╝${NC}

${BOLD}Dotfiles location:${NC}
  ~/.stow_repository (managed by GNU Stow)

${BOLD}To re-run the setup:${NC}
  Run the installer again with: bash <(curl -fsSL ...)

${BOLD}Next steps:${NC}
  ${GREEN}1.${NC} Authenticate with GitHub:  ${BOLD}gh auth login${NC}
  ${GREEN}2.${NC} Authenticate with GitLab:  ${BOLD}glab auth login${NC}
  ${GREEN}3.${NC} Restart your terminal to load new configurations

${BLUE}For more information:${NC}
  ${BLUE}https://github.com/walid-mos/dotfiles/tree/main/mac-setup${NC}

EOF
}

show_usage() {
  cat << EOF
${BOLD}Mac Setup Bootstrap Installer${NC}

${BOLD}USAGE:${NC}
  $0 [OPTIONS]

${BOLD}DESCRIPTION:${NC}
  Bootstrap installer for mac-setup automation.
  Downloads and executes the macOS setup script from:
    ${REPO_URL}

${BOLD}OPTIONS:${NC}
  ${BOLD}-h, --help${NC}         Show this help message and exit
  ${BOLD}-y, --yes${NC}          Skip confirmation prompt (unattended mode)
  ${BOLD}--unattended${NC}       Same as --yes

  ${BOLD}All other options are passed directly to setup.sh:${NC}
    ${BOLD}--dry-run${NC}        Preview installation without making changes
    ${BOLD}--verbose${NC}        Enable verbose output
    ${BOLD}--module <name>${NC}  Run only specific module
    ${BOLD}--skip <name>${NC}    Skip specific module

${BOLD}EXAMPLES:${NC}
  ${BOLD}Interactive installation (recommended for first run):${NC}
    $0

  ${BOLD}Unattended installation (no confirmation):${NC}
    $0 --yes

  ${BOLD}Preview what would be done:${NC}
    $0 --dry-run

  ${BOLD}Unattended with verbose output:${NC}
    $0 --yes --verbose

  ${BOLD}Install only specific modules:${NC}
    $0 --module brew-packages
    $0 --skip clone-repos

${BOLD}REQUIREMENTS:${NC}
  - macOS (Darwin)
  - bash 3.2 or higher
  - git (Xcode Command Line Tools)
  - curl (pre-installed on macOS)

${BOLD}MORE INFO:${NC}
  ${BLUE}https://github.com/walid-mos/dotfiles/tree/main/mac-setup${NC}

EOF
}

# -----------------------------------------------------------------------------
# Main Function
# -----------------------------------------------------------------------------

main() {
  local UNATTENDED="false"
  local SETUP_ARGS=()

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_usage
        exit 0
        ;;
      -y|--yes|--unattended)
        UNATTENDED="true"
        shift
        ;;
      *)
        # Pass unknown arguments to setup.sh
        SETUP_ARGS+=("$1")
        shift
        ;;
    esac
  done

  # Execute installation steps
  check_prerequisites
  show_summary
  confirm_installation
  clone_repository
  run_setup
  show_success_message
}

# =============================================================================
# Execute main function
# (Function wrapping prevents partial execution if network fails mid-download)
# =============================================================================

main "$@"
