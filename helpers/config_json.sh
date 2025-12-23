#!/bin/sh
# helpers/config_json.sh — gestion configuration JSON
# Dépend de: jq, paths.sh (KSYNC_JSON_FILE)
# Lecture + évaluation + persistance en une seule passe.
# Règles:
# - ENV existe ?  -> si valide: ENV(normalisée) ; si invalide: (critical? "") : default
# - ENV absente ? -> si .value != null: .value (de confiance) ; sinon: default

# --- Normalisations (validation) ---

_norm_bool() {
  case "$1" in
    true|TRUE|True|1|yes|on|YES|ON)   echo true ;;
    false|FALSE|False|0|no|off|NO|OFF) echo false ;;
    *) return 1 ;;
  esac
}

_norm_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$1"
}

_norm_string() {
  printf '%s\n' "$1"
}

# Un élément cron valide (sans virgule)
_cron_elem() {
  case "$1" in
    '*'|'*/'[0-9]*|[0-9]*|[0-9]*'-'[0-9]*|[0-9]*'/'[0-9]*|[0-9]*'-'[0-9]*'/'[0-9]*)
      return 0 ;;
    *)
      return 1 ;;
  esac
}

_norm_cron() {
  v=$1

  # Garde-fous caractères globaux
  case "$v" in
    *[!0-9\ \,\-\*\/]* ) return 1 ;;
  esac

  # 5 champs
  set -f; set -- $v; set +f
  [ $# -eq 5 ] || return 1

  # Chaque champ peut être une liste séparée par virgules
  for field in "$@"; do
    [ -n "$field" ] || return 1
    oldifs=$IFS
    IFS=,
    set -- $field
    IFS=$oldifs
    ok=1
    for part in "$@"; do
      _cron_elem "$part" || { ok=0; break; }
    done
    [ "$ok" -eq 1 ] || return 1
  done

  printf '%s\n' "$v"
}

_norm_choice() {
  v=$1
  csv=$2
  oldifs=$IFS
  IFS=,
  set -- $csv
  IFS=$oldifs
  for o in "$@"; do
    o=${o# }; o=${o% }
    [ "$v" = "$o" ] && { echo "$v"; return 0; }
  done
  return 1
}

_is_known_type() {
  case "$1" in
    bool|int|string|cron|choice) return 0 ;;
    *) return 1 ;;
  esac
}

_normalize() {
  t=$1; v=$2; c=${3-}
  case "$t" in
    bool)   _norm_bool   "$v" ;;
    int)    _norm_int    "$v" ;;
    string) _norm_string "$v" ;;
    cron)   _norm_cron   "$v" ;;
    choice) _norm_choice "$v" "$c" ;;
    *)      return 2 ;;  # type vide/inconnu
  esac
}

# --- Lecture + persistance immédiate ---
kcfg_load_and_persist() {
  : "${KSYNC_JSON_FILE:=/var/lib/webdav-sync/webdav-sync-internal.json}"

  [ -f "$KSYNC_JSON_FILE" ] || { echo "{}" >"$KSYNC_JSON_FILE"; chmod 600 "$KSYNC_JSON_FILE" 2>/dev/null || :; }

  KSYNC_CONFIG_ERROR=false

  # On travaille dans un tmp et on met à jour .value clé par clé
  tmp=$(mktemp)
  jq '.' "$KSYNC_JSON_FILE" >"$tmp" 2>/dev/null || echo "{}" >"$tmp"

  # key \t json_value(or empty) \t default \t type \t choices_csv \t critical(true/false)
  list=$(mktemp)
  jq -r '
    to_entries
    | sort_by(.key)[]
    | select(.value|type=="object")
    | "\(.key)\t\(.value.value // empty)\t\(.value.default // empty)\t\(.value.type // empty)\t\((.value.choices // [])|join(","))\t\(.value.critical // false)"
  ' "$tmp" > "$list"

  while IFS="$(printf '\t')" read -r k json_v def_v typ chs critical; do
    final=""

    # ENV définie (même vide) ?
    if printenv "$k" >/dev/null 2>&1; then
      have_env=1
      user_v=$(printenv "$k")
    else
      have_env=0
      user_v=
    fi

    if [ "$have_env" -eq 1 ]; then
      if _is_known_type "$typ"; then
        if user_norm=$(_normalize "$typ" "$user_v" "$chs" 2>/dev/null); then
          final="$user_norm"
        else
          case "$critical" in
            true|True|TRUE|1) final=""; KSYNC_CONFIG_ERROR=true ;;
            *)                final="$def_v" ;;
          esac
        fi
      else
        case "$critical" in
          true|True|TRUE|1) final=""; KSYNC_CONFIG_ERROR=true ;;
          *)                final="$def_v" ;;
        esac
      fi
    else
      # Pas d'ENV: si .value présente on la prend, sinon défaut
      if [ -n "$json_v" ]; then
        final="$json_v"
      else
        final="$def_v"
      fi
    fi

    # Export immédiat pour le reste du script (sans eval)
    export "${k}=$final"

    # Écrit immédiatement .value=final dans le JSON tmp
    jq --arg k "$k" --arg v "$final" '.[$k].value = $v' "$tmp" >"${tmp}.new" && mv -f "${tmp}.new" "$tmp"
  done < "$list"

  rm -f "$list"

  # Commit du JSON
  mv -f "$tmp" "$KSYNC_JSON_FILE"
  chmod 600 "$KSYNC_JSON_FILE" 2>/dev/null || :

  export KSYNC_CONFIG_ERROR
}