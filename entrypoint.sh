#!/bin/sh
# entrypoint.sh — point d'entrée principal du container
set -eu

# === Helpers ===
. /helpers/paths.sh
. /helpers/secrets.sh
. /helpers/user.sh
. /helpers/logs.sh
. /helpers/sync.sh
. /helpers/cron.sh
. /helpers/status.sh
. /helpers/config_json.sh
. /helpers/web.sh
. /helpers/live.sh
. /helpers/snapshot.sh
. /helpers/kctl.sh
. /helpers/control.sh

# === Init ===
load_remote_secrets
kcfg_load_and_persist
apply_timezone


# === Wrapper exécution + collecte status ===
do_run() {
  status_on_start
  rc=0
  if ! run_once; then
    rc=$?
  fi
  status_on_end "$rc"
  return "$rc"
}


# === Modes ===
case "${1:-}" in
  live)
    cgi_header
    live_collect
    exit 0
    ;;

  snapshot)
    cgi_header
    # Parse query string: type=static|dynamic|full (default: full)
    _type=$(printf '%s' "${QUERY_STRING:-}" | sed -n 's/.*type=\([a-z]*\).*/\1/p')
    snapshot_collect "${_type:-full}"
    exit 0
    ;;

  control)
    cgi_header
    control_collect
    exit 0
    ;;

  logs)
    cgi_header
    # Parse query string: lines=N&date=YYYY-MM-DD
    _lines=$(printf '%s' "${QUERY_STRING:-}" | sed -n 's/.*lines=\([0-9]*\).*/\1/p')
    _date=$(printf '%s' "${QUERY_STRING:-}" | sed -n 's/.*date=\([0-9-]*\).*/\1/p')
    logs_collect "${_lines:-100}" "${_date:-today}"
    exit 0
    ;;

  cron-run)
    setup_user
    start_web_if_needed  

    log_info "Run automatique (CRON activé)"
    do_run
    exit $?
    ;;

  "")
    setup_user
    start_web_if_needed

    if [ "${CRON_ENABLED:-false}" = true ]; then
      if [ -z "${CRON_SCHEDULE:-}" ]; then
        log_error "CRON activé mais CRON_SCHEDULE est vide."
        exit 2
      fi

      log_info "Planification : CRON_SCHEDULE='${CRON_SCHEDULE}'"
      write_cron_wrapper
      install_crontab
      start_cron_foreground
    else
      log_info "Run manuel (CRON désactivé)"
      do_run
      exit $?
    fi
    ;;

  *)
    log_error "Argument invalide : '$1'."
    exit 1

    ;;
esac


