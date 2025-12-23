#!/bin/sh
# helpers/control.sh — CGI pour contrôler rclone (start/pause/stop)
# Dépend de: paths.sh (_now), kctl.sh (kctl), live.sh (live_collect)

# Parse QUERY_STRING: action=xxx
_parse_qs() {
  action=""
  oldIFS="$IFS"
  IFS='&'
  set -- $QUERY_STRING
  IFS="$oldIFS"
  for pair in "$@"; do
    k="${pair%%=*}"
    v="${pair#*=}"
    case "$k" in
      action) action="$v" ;;
    esac
  done
}

# Retourne un JSON combinant le résultat de l'action + l'état live
_emit_result() {
  ok="$1"
  action="$2"
  msg="$3"

  # Petit délai pour laisser l'action prendre effet
  sleep 0.3

  # Collecter l'état live actuel
  live_json="$(live_collect)"

  # Combiner action result + live
  jq -n \
    --argjson ok "$ok" \
    --arg action "$action" \
    --arg message "$msg" \
    --argjson live "$live_json" \
    '{ok: $ok, action: $action, message: $message, live: $live}'
}

control_collect() {
  _parse_qs

  case "$action" in
    start)
      # Lance une sync en arrière-plan si pas déjà active
      kctl live
      if [ "${KCTL_RC:-1}" -ne 0 ]; then
        # Pas de sync en cours, on en lance une
        # setsid détache complètement le processus pour éviter les zombies
        setsid /entrypoint.sh cron-run </dev/null >/dev/null 2>&1 &
        sleep 1  # Laisser le temps au process de démarrer
        _emit_result true "start" "sync started"
      else
        _emit_result true "start" "sync already running"
      fi
      ;;
    pause)
      kctl pause
      if [ "${KCTL_RC:-1}" -eq 0 ]; then
        _emit_result true "pause" "paused"
      else
        _emit_result false "pause" "pause failed"
      fi
      ;;
    resume)
      kctl resume
      if [ "${KCTL_RC:-1}" -eq 0 ]; then
        _emit_result true "resume" "resumed"
      else
        _emit_result false "resume" "resume failed"
      fi
      ;;
    stop)
      # Si en pause, d'abord réveiller le processus
      if [ -f "$PAUSE_FLAG_FILE" ]; then
        kctl resume
      fi
      kctl quit
      # Toujours nettoyer le flag de pause
      rm -f "$PAUSE_FLAG_FILE"
      if [ "${KCTL_RC:-1}" -eq 0 ]; then
        # Attendre que rclone se termine vraiment
        sleep 1
        # Retourner directement inactive
        jq -n \
          --argjson ok true \
          --arg action "stop" \
          --arg message "stopped" \
          --arg ts "$(_now)" \
          '{ok: $ok, action: $action, message: $message, live: {status: "inactive", extracted_at: $ts}}'
      else
        _emit_result false "stop" "stop failed"
      fi
      ;;
    *)
      printf '{"ok":false,"error":"unknown action","action":"%s"}\n' "$action"
      ;;
  esac
}
