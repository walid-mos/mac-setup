# Automatisations

Ce dossier contient des scripts d'automatisation personnalisés qui s'exécutent après les modules principaux du setup.

## Comment ça fonctionne

Les scripts dans ce dossier sont **automatiquement découverts et exécutés** par le module `automatisations` :

- **Découverte automatique** : Tous les fichiers `.sh` dans ce dossier sont détectés
- **Ordre alphabétique** : Les scripts s'exécutent dans l'ordre alphabétique de leur nom
- **Configuration TOML** : Activation globale et individuelle via `mac-setup.toml`
- **Gestion interactive des erreurs** : En cas d'échec, le système demande si continuer ou arrêter

## Configuration

### Activation globale

Dans `mac-setup.toml` :

```toml
[automations]
enabled = true  # Master switch pour activer/désactiver toutes les automatisations
```

### Activation/désactivation individuelle

Pour chaque script, vous pouvez contrôler son exécution :

```toml
[automations]
enabled = true

# Nom du script (sans .sh) = true/false
backup-databases = true
sync-configs = false
custom-setup = true
```

**Par défaut** : Si un script n'est pas mentionné dans la config, il s'exécute quand même (si `enabled = true`)

## Convention de nommage

### Nom du fichier
- Format : `<action-description>.sh`
- Style : **kebab-case** (minuscules avec tirets)
- Exemples : `backup-databases.sh`, `sync-configs.sh`, `install-fonts.sh`

### Nom de la fonction principale
- Format : `automation_<action_description>`
- Style : **snake_case** (minuscules avec underscores)
- Exemples : `automation_backup_databases`, `automation_sync_configs`

### Identifiant dans TOML
- Même nom que le fichier **sans l'extension** `.sh`
- Exemples : `backup-databases`, `sync-configs`

## Template de script

Voici la structure recommandée pour un script d'automatisation :

```bash
#!/usr/bin/env bash

# ============================================================================
# Description courte de ce que fait l'automatisation
# ============================================================================

set -euo pipefail

# Source libraries (si exécuté standalone)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
fi

# ============================================================================
# Main automation function
# ============================================================================
automation_my_task() {
  log_info "Démarrage de l'automatisation my-task..."

  # Vérifications préalables
  if ! command -v some_tool &> /dev/null; then
    log_error "some_tool n'est pas installé"
    return 1
  fi

  # Support du mode dry-run
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would execute: some_command"
    return 0
  fi

  # Logique principale
  log_step "Étape 1 : Description"
  if some_command; then
    log_success "Étape 1 terminée"
  else
    log_error "Échec de l'étape 1"
    return 1
  fi

  log_step "Étape 2 : Description"
  # ...

  log_success "Automatisation my-task terminée avec succès"
  return 0
}

# ============================================================================
# Standalone execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_my_task
fi
```

## Bonnes pratiques

### 1. Idempotence
Vos scripts doivent pouvoir être exécutés plusieurs fois sans causer de problèmes :

```bash
# ✅ BON : Vérifier avant d'agir
if [[ ! -d "$HOME/.config/myapp" ]]; then
  mkdir -p "$HOME/.config/myapp"
fi

# ❌ MAUVAIS : Peut échouer si déjà existant
mkdir "$HOME/.config/myapp"
```

### 2. Gestion d'erreurs
Retournez des codes appropriés :

```bash
# Succès
return 0

# Échec
return 1
```

### 3. Logging cohérent
Utilisez les fonctions de logging fournies :

```bash
log_info "Information"
log_step "Étape en cours"
log_success "Opération réussie"
log_warning "Avertissement"
log_error "Erreur"
```

### 4. Support du dry-run
Toujours respecter le mode dry-run :

```bash
if [[ "$DRY_RUN" == "true" ]]; then
  log_info "[DRY RUN] Would execute: dangerous_command"
  return 0
fi

dangerous_command
```

### 5. Configuration via TOML (optionnel)
Si votre automatisation a besoin de configuration :

```bash
# Dans votre script
local my_setting
my_setting=$(parse_toml_value "$TOML_CONFIG" "automations.my-task.setting")

if [[ -n "$my_setting" ]]; then
  log_info "Using custom setting: $my_setting"
fi
```

```toml
# Dans mac-setup.toml
[automations.my-task]
setting = "custom_value"
```

## Exemples d'automatisations

### Exemple 1 : Backup de configuration

```bash
# automatisations/backup-configs.sh
automation_backup_configs() {
  local backup_dir="$HOME/.config-backups"
  local timestamp=$(date +%Y%m%d_%H%M%S)

  log_info "Création d'un backup des configurations..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would backup configs to $backup_dir/$timestamp"
    return 0
  fi

  mkdir -p "$backup_dir/$timestamp"

  for config in "$HOME/.zshrc" "$HOME/.gitconfig"; do
    if [[ -f "$config" ]]; then
      cp "$config" "$backup_dir/$timestamp/"
      log_success "Backed up: $(basename "$config")"
    fi
  done

  return 0
}
```

### Exemple 2 : Installation de polices

```bash
# automatisations/install-fonts.sh
automation_install_fonts() {
  local fonts_dir="$HOME/Library/Fonts"
  local source_dir
  source_dir=$(parse_toml_value "$TOML_CONFIG" "automations.install-fonts.source")

  if [[ -z "$source_dir" ]]; then
    log_warning "Aucun dossier source défini dans la config"
    return 0
  fi

  log_info "Installation des polices depuis $source_dir..."

  if [[ ! -d "$source_dir" ]]; then
    log_error "Le dossier source n'existe pas: $source_dir"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would copy fonts from $source_dir to $fonts_dir"
    return 0
  fi

  find "$source_dir" -type f \( -name "*.ttf" -o -name "*.otf" \) -exec cp {} "$fonts_dir/" \;

  log_success "Polices installées"
  return 0
}
```

## Exécution

### Via le script principal

```bash
# Exécuter tout le setup (y compris les automatisations)
./setup.sh

# Exécuter seulement les automatisations
./setup.sh --module automatisations

# Exécuter tout SAUF les automatisations
./setup.sh --skip automatisations

# Mode dry-run
./setup.sh --dry-run --module automatisations
```

### Exécution standalone

Chaque script peut être exécuté individuellement :

```bash
./automatisations/backup-configs.sh
```

## Désactivation

### Désactiver toutes les automatisations

```toml
[automations]
enabled = false
```

### Désactiver une automatisation spécifique

```toml
[automations]
enabled = true
backup-configs = false  # Cette automatisation sera ignorée
```

## Débogage

Les automatisations utilisent le même système de logging que les modules principaux. Les logs sont visibles dans la console avec des couleurs pour faciliter le débogage.

Pour plus de détails sur une erreur, vous pouvez :

1. Exécuter le script en standalone
2. Utiliser le mode dry-run pour voir ce qui serait exécuté
3. Consulter les logs dans la console

## Questions fréquentes

**Q: Que se passe-t-il si une automatisation échoue ?**
R: Le système vous demande si vous voulez continuer avec les autres automatisations ou arrêter complètement.

**Q: Dans quel ordre s'exécutent les scripts ?**
R: Ordre alphabétique par nom de fichier. Utilisez des préfixes numériques si vous voulez un ordre spécifique (ex: `01-first.sh`, `02-second.sh`).

**Q: Puis-je passer des paramètres à mes automatisations ?**
R: Oui, via la configuration TOML. Utilisez `parse_toml_value()` dans votre script.

**Q: Comment tester mon automatisation sans modifier le système ?**
R: Utilisez le mode dry-run : `./setup.sh --dry-run --module automatisations`

**Q: Mes automatisations peuvent-elles dépendre d'autres modules ?**
R: Oui ! Les automatisations s'exécutent APRÈS tous les modules principaux, donc tout ce qui est installé par les modules est disponible.
