#!/bin/sh
# helpers/user.sh — gestion timezone, utilisateur et permissions
# Dépend de: paths.sh (LIB_DIR, LOCAL_DIR, etc.), logs.sh (log_warn)

# apply_timezone -> applique le fuseau horaire défini dans $TZ
apply_timezone() {
  if [ -n "${TZ:-}" ] && [ -e "/usr/share/zoneinfo/$TZ" ]; then
    # tente de mettre à jour /etc/localtime (silencieusement si pas root)
    ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime 2>/dev/null || true

    # n'écrit /etc/timezone que si on a la permission d'écriture
    if [ -w /etc/timezone ] || [ ! -e /etc/timezone ] && [ -w "$(dirname /etc/timezone)" ]; then
      { echo "$TZ" > /etc/timezone; } 2>/dev/null || true
    fi
    # TZ est déjà exportée par l'environnement
  fi
}

# setup_user -> crée un utilisateur/groupe correspondant à PUID/PGID, puis ajuste les droits
setup_user() {
  if [ "${PUID:-0}" -eq 0 ] && [ "${PGID:-0}" -eq 0 ]; then
    # root intégral, rien à faire
    export HOME="${LIB_DIR}"
    return 0
  fi

  # Crée le groupe si absent (idempotent)
  if ! grep -qE "^rclonegrp:x:${PGID}:" /etc/group 2>/dev/null; then
    addgroup -S -g "$PGID" rclonegrp 2>/dev/null || true
  fi

  # Crée l'utilisateur si absent (idempotent)
  if ! grep -qE "^rcloneusr:x:${PUID}:" /etc/passwd 2>/dev/null; then
    adduser -S -D -H -u "$PUID" -G rclonegrp -s /sbin/nologin rcloneusr 2>/dev/null || true
  fi

  # Propriété des répertoires de travail/état
  for d in "$LOCAL_DIR" "$LOG_DIR" "$LIB_DIR" "$STATUS_DIR"; do
    [ -d "$d" ] && chown -R "$PUID:$PGID" "$d" 2>/dev/null || true
  done

  # HOME logique pour l'utilisateur non-root
  export HOME="${LIB_DIR}"
}

# ensure_effective_user -> si l'UID/GID effectifs ne correspondent pas à PUID/PGID,
# re-exécute le script courant avec le bon utilisateur/groupe.
ensure_effective_user() {
  # Si on veut rester root, ou si déjà au bon UID/GID -> rien à faire
  cur_uid="$(id -u 2>/dev/null || echo 0)"
  cur_gid="$(id -g 2>/dev/null || echo 0)"

  want_uid="${PUID:-0}"
  want_gid="${PGID:-0}"

  # Normalise (valeurs vides -> 0)
  [ -n "$want_uid" ] || want_uid=0
  [ -n "$want_gid" ] || want_gid=0

  if [ "$want_uid" -eq 0 ] && [ "$want_gid" -eq 0 ]; then
    return 0
  fi

  if [ "$cur_uid" -eq "$want_uid" ] && [ "$cur_gid" -eq "$want_gid" ]; then
    return 0
  fi

  # Choisit l'outil de switch le plus adapté
  if command -v su-exec >/dev/null 2>&1; then
    # su-exec <uid:gid> <cmd> ...
    exec su-exec "${want_uid}:${want_gid}" "$0" "$@"
  elif command -v gosu >/dev/null 2>&1; then
    # gosu <uid:gid> <cmd> ...
    exec gosu "${want_uid}:${want_gid}" "$0" "$@"
  elif command -v setpriv >/dev/null 2>&1; then
    # setpriv (util-linux) / busybox setpriv : --reuid/--regid/--init-groups
    exec setpriv --reuid "$want_uid" --regid "$want_gid" --init-groups "$0" "$@"
  elif command -v busybox >/dev/null 2>&1 && busybox setpriv 2>/dev/null | grep -q setpriv; then
    # fallback explicite via busybox
    exec busybox setpriv --reuid "$want_uid" --regid "$want_gid" --init-groups "$0" "$@"
  else
    # Aucun outil dispo : on continue en l'état (on logge seulement)
    log_warn "Aucun utilitaire de drop-privileges disponible (su-exec/gosu/setpriv). Exécution en UID=$cur_uid,GID=$cur_gid."
    return 0
  fi
}