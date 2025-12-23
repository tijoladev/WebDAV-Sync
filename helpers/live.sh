#!/bin/sh
# helpers/live.sh — CGI stats temps réel
# Dépend de: paths.sh (_now, PAUSE_FLAG_FILE), kctl.sh (kctl)

live_collect() {
  ts="$(_now)"

  # Vérifier si en pause via le fichier flag (AVANT d'appeler l'API RC)
  is_paused="false"
  [ -f "$PAUSE_FLAG_FILE" ] && is_paused="true"

  # Si en pause, ne pas appeler l'API RC (le processus est SIGSTOP et ne répondra pas)
  if [ "$is_paused" = "true" ]; then
    jq -n \
      --arg ts "$ts" \
      '{status:"paused",extracted_at:$ts,stats:null,debug:{cmd:"skipped (paused)",rc:0,stderr:""}}'
    return 0
  fi

  # Appel via le driver kctl (ne casse pas le pipeline et exporte KCTL_*)
  kctl live

  # Si stdout semble être un JSON et rc==0 -> statut "active"
  if [ "${KCTL_RC:-1}" -eq 0 ] \
     && [ -n "${KCTL_STDOUT:-}" ] \
     && printf '%s' "$KCTL_STDOUT" | jq -e . >/dev/null 2>&1
  then
    printf '%s' "$KCTL_STDOUT" | jq \
      --arg ts "$ts" \
      --arg rc "${KCTL_RC:-1}" \
      --arg err "${KCTL_STDERR:-}" \
      '{
        status: "active",
        extracted_at: $ts,
        stats: .,
        debug: {
          cmd: "wdsync live",
          rc: ($rc|tonumber),
          stderr: $err
        }
      }'
    return 0
  fi

  # Sinon -> statut "inactive" + debug
  jq -n \
    --arg ts "$ts" \
    --argjson rc "${KCTL_RC:-1}" \
    --arg out "$(printf '%s' "${KCTL_STDOUT:-}" | head -c 500)" \
    --arg err "$(printf '%s' "${KCTL_STDERR:-}" | head -c 500)" \
    '{status:"inactive",extracted_at:$ts,debug:{cmd:"wdsync live",rc:$rc,stdout:$out,stderr:$err}}'
}