#!/bin/sh
# /usr/local/bin/wdsync — utilitaire CLI pour webdav-sync (sortie JSON uniforme)
set -eu

# === Helpers ===
. /helpers/paths.sh
. /helpers/secrets.sh
. /helpers/user.sh
. /helpers/logs.sh
. /helpers/sync.sh
. /helpers/status.sh
. /helpers/config_json.sh

usage() {
  cat <<'EOF'
Usage: wdsync <commande>

Commandes :
  check-remote     Vérifie si le remote WebDAV est présent
  init-remote      (Ré)initialise le remote depuis REMOTE_*
  about-remote     Affiche les infos "about" du remote (JSON)
  version          Affiche la version de rclone (texte)
  recents-files    Liste les fichiers récents (24h) en CSV
  live             Interroge l'état live (RC API si up)
  op               Exécute l'opération rclone configurée (sync/copy...)
  quit             Arrête proprement l'instance rclone (RC core/quit)
  pause            Suspend le transfert (SIGSTOP)
  resume           Reprend le transfert (SIGCONT)

Retour JSON uniforme : {cmd, rc, stdout, stderr, data, artifact, start_at, end_at, duration_s}
EOF
}

# === Pré-init commun ===
preinit() {
  kcfg_load_and_persist
  apply_timezone
  ensure_effective_user "$@"
}

# === Exécuteur générique avec enveloppe JSON ===
run_json() {
  start="$(_now)"
  t0=$(date +%s || echo 0)

  outf="$(mktemp)"
  erf="$(mktemp)"

  if "$@" >"$outf" 2>"$erf"; then
    rc=0
  else
    rc=$?
  fi

  end="$(_now)"
  t1=$(date +%s || echo 0)
  dur=$(( t1 - t0 ))

  out="$(cat "$outf" 2>/dev/null || true)"
  err="$(cat "$erf" 2>/dev/null || true)"

  cmd_str=""
  for a in "$@"; do
    case "$a" in *$'\n'* ) a=$(printf '%s' "$a" | tr '\n' ' ') ;; esac
    [ -z "$cmd_str" ] && cmd_str="$a" || cmd_str="$cmd_str $a"
  done

  jq -n \
    --arg cmd "$cmd_str" \
    --arg start "$start" \
    --arg end "$end" \
    --arg out "$out" \
    --arg err "$err" \
    --argjson rc "$rc" \
    --argjson dur "$dur" \
    '{
       cmd: $cmd,
       rc: $rc,
       stdout: $out,
       stderr: $err,
       data: null,
       artifact: null,
       start_at: $start,
       end_at: $end,
       duration_s: $dur
     }'

  rm -f "$outf" "$erf" 2>/dev/null || :
  return "$rc"
}

# === Commandes ===

cmd_check_remote() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json sh -c "rclone $log_opt listremotes --config '$RCLONE_CONF_FILE' | grep -Fx '${REMOTE_ALIAS}:'"
}

cmd_init_remote() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json sh -c "rclone $log_opt config create '${REMOTE_ALIAS}' webdav \
    url '$REMOTE_URL' vendor 'other' user '$REMOTE_USER' pass '$REMOTE_PASS_OBSCURED' \
    --config '$RCLONE_CONF_FILE' --non-interactive --no-obscure"
}

cmd_about_remote() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json rclone $log_opt about "${REMOTE_ALIAS}:" --config "$RCLONE_CONF_FILE" --json
}

cmd_version() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json rclone $log_opt version
}

cmd_recents_files() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json rclone $log_opt lsjson "${REMOTE_ALIAS}:" --config "$RCLONE_CONF_FILE" --max-age 24h --files-only --recursive
}

cmd_live() {
  preinit "$@"
  # Pas de log_opt ici : -q suffit pour ne pas polluer la sortie
  run_json rclone -q rc core/stats --rc-addr "$RC_ADDR" --rc-no-auth --timeout 3s
}

cmd_op() {
  preinit "$@"
  local log_opt; log_opt="$(log_file_helper arg || true)"
  run_json rclone $log_opt "$SYNC_OP" "${REMOTE_ALIAS}:/" "$LOCAL_DIR" \
    --config "$RCLONE_CONF_FILE" $SYNC_FLAGS \
    --rc --rc-addr "$RC_ADDR" --rc-no-auth
}

# Arrêter proprement rclone (RC)
cmd_quit() {
  preinit "$@"
  # core/quit retourne généralement rc=0 si l'instance RC est joignable
  run_json rclone -q rc core/quit --rc-addr "$RC_ADDR" --rc-no-auth --timeout 3s
}

# Trouve le PID du processus rclone en cours
_find_rclone_pid() {
  pgrep -f "rclone.*--rc-addr.*$RC_ADDR" 2>/dev/null | head -1
}

# Pause : envoie SIGSTOP au processus rclone
cmd_pause() {
  preinit "$@"
  pid=$(_find_rclone_pid)
  if [ -z "$pid" ]; then
    run_json sh -c "echo 'no rclone process found' >&2; exit 1"
    return
  fi
  # Marquer comme en pause
  touch "$PAUSE_FLAG_FILE"
  run_json kill -STOP "$pid"
}

# Resume : envoie SIGCONT au processus rclone
cmd_resume() {
  preinit "$@"
  pid=$(_find_rclone_pid)
  if [ -z "$pid" ]; then
    run_json sh -c "echo 'no rclone process found' >&2; exit 1"
    return
  fi
  # Retirer le marqueur de pause
  rm -f "$PAUSE_FLAG_FILE"
  run_json kill -CONT "$pid"
}

# === Dispatch ===
cmd="${1:-}"
case "$cmd" in
  check-remote)    cmd_check_remote "$@" ;;
  init-remote)     cmd_init_remote "$@" ;;
  about-remote)    cmd_about_remote "$@" ;;
  version)         cmd_version "$@" ;;
  recents-files)   cmd_recents_files "$@" ;;
  live)            cmd_live "$@" ;;
  op)              cmd_op "$@" ;;
  quit)            cmd_quit "$@" ;;
  pause)           cmd_pause "$@" ;;
  resume)          cmd_resume "$@" ;;
  ""|help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac