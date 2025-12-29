#!/usr/bin/env bash

# =============================================================================
# TOML Parser
# =============================================================================
# Parse TOML configuration files using dasel.
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
  ver=$(dasel --version 2>/dev/null || dasel version 2>/dev/null)
  echo "$ver" | grep -oE '[0-9]+' | head -1
}

# -----------------------------------------------------------------------------
# Run dasel with version-appropriate syntax
# Usage: run_dasel <file> <selector>
# -----------------------------------------------------------------------------
run_dasel() {
  local file="$1"
  local selector="$2"
  local major_ver
  major_ver=$(get_dasel_major_version)

  if [[ "$major_ver" == "2" ]]; then
    dasel -f "$file" -r toml "$selector" 2>/dev/null
    return $?
  fi

  if [[ "$major_ver" == "3" ]]; then
    dasel -i toml "$selector" < "$file" 2>/dev/null
    return $?
  fi

  log_error "Unsupported dasel version: $major_ver (expected 2 or 3)"
  return 1
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

  run_dasel "$file" "$key" || echo ""
}

# -----------------------------------------------------------------------------
# Parse TOML array
# -----------------------------------------------------------------------------
parse_toml_array() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    log_error "TOML file not found: $file"
    return 1
  fi

  run_dasel "$file" "$key.all()" | sed "s/^'//" | sed "s/'$//" || echo ""
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

  local dasel_ver
  dasel_ver=$(dasel --version 2>/dev/null || dasel version 2>/dev/null)
  log_verbose "Using dasel for TOML parsing (${dasel_ver})"
  return 0
}
