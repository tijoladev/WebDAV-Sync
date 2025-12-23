#!/bin/sh
# helpers/kctl.sh — interface simplifiée pour wdsync
# Dépend de: wdsync (binaire)

# --- Driver wdsync ---
# Variables "de sortie" globales après chaque appel :
#   KCTL_RC       ← entier (champ .rc)
#   KCTL_STDOUT   ← texte (champ .stdout)
#   KCTL_STDERR   ← texte (champ .stderr)
#
# Remarques :
# - La fonction ne casse jamais le pipeline : elle retourne toujours 0.
# - Les variables KCTL_* sont exportées dans l'environnement courant.

kctl() {
  # Usage: kctl <args...>      # ex: kctl about-remote
  local res
  res="$(wdsync "$@" 2>/dev/null || true)"

  KCTL_RC=$(printf '%s' "$res" | jq -r '.rc // 1' 2>/dev/null || echo 1)
  KCTL_STDOUT=$(printf '%s' "$res" | jq -r '.stdout // ""' 2>/dev/null || echo "")
  KCTL_STDERR=$(printf '%s' "$res" | jq -r '.stderr // ""' 2>/dev/null || echo "")

  export KCTL_RC KCTL_STDOUT KCTL_STDERR
  return 0
}

# --- Aides de lecture ---

# Renvoie stdout si c’est un JSON non vide et que rc==0, sinon {}.
kctl_stdout_json_or_empty() {
  if [ "${KCTL_RC:-1}" -eq 0 ] && [ -n "${KCTL_STDOUT:-}" ]; then
    printf '%s' "$KCTL_STDOUT"
  else
    printf '{}'
  fi
}

# Renvoie stdout seulement si rc==0 (sinon chaîne vide)
kctl_stdout_or_empty() {
  if [ "${KCTL_RC:-1}" -eq 0 ]; then
    printf '%s' "$KCTL_STDOUT"
  else
    printf ''
  fi
}

# Renvoie stderr seulement si non vide (pratique pour logs)
kctl_stderr_or_empty() {
  [ -n "${KCTL_STDERR:-}" ] && printf '%s' "$KCTL_STDERR" || printf ''
}