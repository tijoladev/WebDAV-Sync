FROM rclone/rclone:1.71.2

# rclone + cron + TZ + utilitaires
RUN apk add --no-cache tzdata ca-certificates su-exec busybox-extras util-linux jq

ENV TZ=Europe/Paris \
    NO_LOG=false \
    LOG_MAX_DAYS=5 \
    LOG_LEVEL=INFO \
    PUID=0 \
    PGID=0 \
    CRON_ENABLED=true \
    CRON_SCHEDULE="0 5 * * *" \
    SYNC_OP=sync \
    SYNC_FLAGS="--fast-list --delete-during" \
    REMOTE_URL= \
    REMOTE_USER= \
    REMOTE_PASS=

# Précréation (optionnelle mais propre)
RUN mkdir -p /var/lib/webdav-sync/www /webdav-sync/local-files /webdav-sync/logs

# Config interne (chemin attendu par helpers/paths.sh)
COPY webdav-sync-internal.json /var/lib/webdav-sync/webdav-sync-internal.json
RUN chmod 600 /var/lib/webdav-sync/webdav-sync-internal.json || true

# UI statique (HTML/CSS/JS)
COPY www/ /var/lib/webdav-sync/www/
# Permissions web : dossiers 755, fichiers 644
RUN find /var/lib/webdav-sync/www -type d -exec chmod 755 {} + \
 && find /var/lib/webdav-sync/www -type f -exec chmod 644 {} +

# Helpers + entrypoint + wdsync
COPY helpers/ /helpers/
COPY entrypoint.sh /entrypoint.sh
COPY wdsync.sh /usr/local/bin/wdsync

RUN chmod 755 /entrypoint.sh /usr/local/bin/wdsync \
 && chmod 644 /helpers/*.sh

VOLUME ["/webdav-sync/local-files", "/webdav-sync/logs"]
EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]