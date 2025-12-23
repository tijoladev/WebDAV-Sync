#!/bin/sh
# helpers/cron.sh — gestion du mode planifié via cron
# Dépend de: logs.sh (log_info)

CRON_DIR="/etc/crontabs"
WRAPPER_DIR="/usr/local/bin"
CRON_WRAPPER="$WRAPPER_DIR/cron-run.sh"

CROND_CMD="crond -f -l 2"
CRON_LOG_STDOUT="/proc/1/fd/1"

# Génère le wrapper minimal : flock + entrypoint (tout est auto-contenu)
write_cron_wrapper() {
  mkdir -p "$WRAPPER_DIR" /var/lock
  cat >"$CRON_WRAPPER" <<'WRAP'
#!/bin/sh
set -eu
CRON_LOCK="/var/lock/rclone.cron.lock"
ENTRYPOINT_CMD="/entrypoint.sh cron-run"
exec flock -n "$CRON_LOCK" -c "$ENTRYPOINT_CMD"
WRAP
  chmod 700 "$CRON_WRAPPER"
}

# Installe la crontab root (BusyBox)
install_crontab() {
  mkdir -p "$CRON_DIR"
  {
    echo "SHELL=/bin/sh"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    printf '%s %s >> %s 2>&1\n' "$CRON_SCHEDULE" "$CRON_WRAPPER" "$CRON_LOG_STDOUT"
  } >"$CRON_DIR/root"
}

# Lance crond en avant-plan
start_cron_foreground() {
  log_info "Crontab chargée : $(cat "$CRON_DIR/root" | tr '\n' ' ')"
  exec $CROND_CMD
}