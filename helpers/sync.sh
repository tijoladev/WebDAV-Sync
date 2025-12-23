#!/bin/sh
# helpers/sync.sh — orchestration WebDAV + rclone via wdsync
# Dépend de: paths.sh, logs.sh (log_info/warn/error), kctl.sh (kctl)

# md5 des secrets (obscurcis) pour savoir si on doit (re)créer le remote
_remote_env_md5() {
  [ -n "${REMOTE_URL:-}" ] && [ -n "${REMOTE_USER:-}" ] && [ -n "${REMOTE_PASS_OBSCURED:-}" ] || { echo ""; return; }
  printf '%s' "${REMOTE_URL}|${REMOTE_USER}|${REMOTE_PASS_OBSCURED}" | md5sum 2>/dev/null | awk '{print $1}'
}

_remote_exists() {
  kctl check-remote
  [ "${KCTL_RC:-1}" -eq 0 ]
}

_create_remote() {
  kctl init-remote
  [ "${KCTL_RC:-1}" -eq 0 ]
}

ensure_remote() {
  mkdir -p "$(dirname "$RCLONE_CONF_FILE")" "$STATUS_DIR"

  local new_md5 old_md5
  new_md5=$(_remote_env_md5)

  if [ -n "$new_md5" ]; then
    [ -f "$REMOTE_MD5_FILE" ] && old_md5=$(cat "$REMOTE_MD5_FILE" 2>/dev/null || echo "") || old_md5=""

    if [ "$new_md5" != "$old_md5" ]; then
      log_warn "Credentials REMOTE_* modifiés → réinitialisation de la configuration rclone."
      rm -f -- "$RCLONE_CONF_FILE"
      _create_remote || { log_error "Échec création remote '${REMOTE_ALIAS}'."; exit 2; }
      umask 077; printf '%s\n' "$new_md5" > "$REMOTE_MD5_FILE"
      return 0
    fi

    if ! _remote_exists; then
      _create_remote || { log_error "Échec création remote '${REMOTE_ALIAS}'."; exit 2; }
    fi

    [ -f "$REMOTE_MD5_FILE" ] || { umask 077; printf '%s\n' "$new_md5" > "$REMOTE_MD5_FILE"; }
    return 0
  fi

  if [ -f "$RCLONE_CONF_FILE" ] && _remote_exists; then
    log_info "REMOTE_* non définies → utilisation de la configuration rclone existante."
    return 0
  fi

  log_error "REMOTE_URL / REMOTE_USER / REMOTE_PASS requis (aucune conf existante utilisable)."
  exit 2
}

run_once() {
  ensure_remote
  rotate_logs
  log_banner

  # Lance l'opération rclone via wdsync (logs + RC gérés côté wdsync)
  kctl op
  return "${KCTL_RC:-1}"
}