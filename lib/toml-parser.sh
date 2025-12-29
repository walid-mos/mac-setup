#!/usr/bin/env bash

# =============================================================================
# TOML Parser
# =============================================================================
# Parse TOML configuration files using dasel.
# Supports both dasel v2 and v3 (different CLI syntax).
# Requires dasel to be installed (handled by script-dependencies module).
# =============================================================================

# -----------------------------------------------------------------------------
# Check if dasel is available
# -----------------------------------------------------------------------------
has_dasel() {
  command_exists dasel
}

# -----------------------------------------------------------------------------
# Get dasel major version (2 or 3)
# -----------------------------------------------------------------------------
get_dasel_major_version() {
  local ver
  # v2 uses --version flag, v3 uses 'version' subcommand
  ver=$(dasel --version 2>/dev/null || dasel version 2>/dev/null)
  echo "$ver" | grep -oE '[0-9]+' | head -1
}

# -----------------------------------------------------------------------------
# Escape key segments containing hyphens for dasel v3
# In v3, hyphens are treated as subtraction operators, so we must quote them
# Example: automations.nas-shares.server -> automations."nas-shares".server
# -----------------------------------------------------------------------------
escape_key_for_v3() {
  local key="$1"
  # Quote any segment that contains a hyphen
  echo "$key" | sed 's/\([^.]*-[^.]*\)/"\1"/g'
}

# -----------------------------------------------------------------------------
# Parse TOML value
# -----------------------------------------------------------------------------
parse_toml_value() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    log_error "TOML file not found: $file"
    return 1
  fi

  local major_ver
  major_ver=$(get_dasel_major_version)

  if [[ "$major_ver" == "2" ]]; then
    dasel -f "$file" -r toml "$key" 2>/dev/null || echo ""
  elif [[ "$major_ver" == "3" ]]; then
    local escaped_key
    escaped_key=$(escape_key_for_v3 "$key")
    dasel -i toml "$escaped_key" < "$file" 2>/dev/null || echo ""
  else
    log_error "Unsupported dasel version: $major_ver"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Parse TOML array (returns one element per line)
# -----------------------------------------------------------------------------
parse_toml_array() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    log_error "TOML file not found: $file"
    return 1
  fi

  local major_ver
  major_ver=$(get_dasel_major_version)

  if [[ "$major_ver" == "2" ]]; then
    # v2: use .all() selector, outputs one per line with quotes
    dasel -f "$file" -r toml "$key.all()" 2>/dev/null | sed "s/^'//" | sed "s/'$//" || echo ""
  elif [[ "$major_ver" == "3" ]]; then
    # v3: returns array as ['item1', 'item2', ...], needs parsing
    # Transform: ['stow', 'fzf'] -> stow\nfzf
    local escaped_key
    escaped_key=$(escape_key_for_v3 "$key")
    dasel -i toml "$escaped_key" < "$file" 2>/dev/null | \
      tr -d '[]' | \
      tr ',' '\n' | \
      sed "s/^[[:space:]]*'//;s/'[[:space:]]*$//" | \
      grep -v '^$' || echo ""
  else
    log_error "Unsupported dasel version: $major_ver"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Get all keys from a TOML section
# -----------------------------------------------------------------------------
get_toml_section_keys() {
  local file="$1"
  local section="$2"

  awk -v section="$section" '
    /^\[/ { in_section=0 }
    /^\['"$section"'\]/ { in_section=1; next }
    in_section && /^\[/ { exit }
    in_section && /^[a-zA-Z_]/ {
      match($0, /^[^=]+/)
      key = substr($0, RSTART, RLENGTH)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      print key
    }
  ' "$file"
}

# -----------------------------------------------------------------------------
# Check if TOML section exists
# -----------------------------------------------------------------------------
toml_section_exists() {
  local file="$1"
  local section="$2"

  grep -q "^\[$section\]" "$file"
}

# -----------------------------------------------------------------------------
# Parse TOML into bash associative array
# -----------------------------------------------------------------------------
parse_toml_to_array() {
  local file="$1"
  local section="$2"
  declare -n arr="$3"  # nameref to associative array

  local keys
  keys="$(get_toml_section_keys "$file" "$section")"

  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    local value
    value="$(parse_toml_value "$file" "$section.$key")"
    arr["$key"]="$value"
  done <<< "$keys"
}

# -----------------------------------------------------------------------------
# Initialize TOML parser
# -----------------------------------------------------------------------------
init_toml_parser() {
  log_verbose "Initializing TOML parser..."

  if ! has_dasel; then
    log_error "dasel is required but not installed"
    log_error "Module script-dependencies should have installed it. This is a bug."
    return 1
  fi

  # Verify dasel actually works (v2.x uses --version, v3.x uses 'version' subcommand)
  if ! dasel --version >/dev/null 2>&1 && ! dasel version >/dev/null 2>&1; then
    log_error "dasel is installed but not functioning correctly"
    log_error "Try reinstalling: brew reinstall dasel"
    return 1
  fi

  local dasel_ver major_ver
  dasel_ver=$(dasel --version 2>/dev/null || dasel version 2>/dev/null)
  major_ver=$(get_dasel_major_version)
  log_verbose "Using dasel v${major_ver} for TOML parsing (${dasel_ver})"
  return 0
}
