#!/bin/sh
# helpers/secrets.sh — lecture sécurisée des secrets
# Dépend de: rclone (pour obscure)
# Lecture sécurisée des secrets avec priorité :
#   /run/secrets/VAR  >  ${VAR}_FILE  >  VAR
# Compatible Docker & Kubernetes (symlinks acceptés).
# Nettoie les fins de ligne CRLF et vérifie les fichiers lisibles.

# resolve_secret VAR
# - stdout: valeur (sans \r), sans newline ajouté par nous (la subshell en enlèvera).
# - exit 0 si une valeur est trouvée (même chaîne vide) ou si absente (on renvoie vide),
#   exit 2 seulement en cas d'erreur d’usage (nom invalide) ou fichier illisible/inexistant référencé.
resolve_secret() {
  var=$1

  # Validation stricte du nom de variable (POSIX-safe)
  case $var in ''|*[!A-Za-z0-9_]*|[0-9]*)
    printf 'Invalid var name: %s\n' "$var" >&2
    return 2
    ;;
  esac

  filevar="${var}_FILE"

  # 1) Docker/K8s secrets : /run/secrets/VAR
  if [ -f "/run/secrets/$var" ]; then
    tr -d '\r' < "/run/secrets/$var"
    return 0
  fi

  # 2) *_FILE si défini (sans eval)
  fpath=$(printenv "$filevar" 2>/dev/null || true)
  if [ -n "$fpath" ]; then
    if [ ! -e "$fpath" ]; then
      printf 'Secret file not found: %s\n' "$fpath" >&2
      return 2
    fi
    if [ -d "$fpath" ] || [ ! -r "$fpath" ]; then
      printf 'Unreadable or directory: %s\n' "$fpath" >&2
      return 2
    fi
    tr -d '\r' < "$fpath"
    return 0
  fi

  # 3) Valeur directe dans l'environnement (sans eval)
  val=$(printenv "$var" 2>/dev/null || true)
  # Pas d'erreur si absente : on renvoie vide et exit 0
  printf %s "$val"
  return 0
}

# load_remote_secrets
# Charge et exporte REMOTE_URL / REMOTE_USER / REMOTE_PASS / REMOTE_PASS_OBSCURED
load_remote_secrets() {
  REMOTE_URL="$(resolve_secret REMOTE_URL)"
  REMOTE_USER="$(resolve_secret REMOTE_USER)"
  REMOTE_PASS="$(resolve_secret REMOTE_PASS)"
  REMOTE_PASS_OBSCURED="$(rclone obscure "$REMOTE_PASS" 2>/dev/null || printf '')"
  export REMOTE_URL REMOTE_USER REMOTE_PASS REMOTE_PASS_OBSCURED
}