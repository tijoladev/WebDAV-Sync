#!/bin/sh
# helpers/auth.sh — HTTP Basic Auth pour BusyBox httpd
# Dépend de: paths.sh (WEB_ROOT), logs.sh (log_info)
#
# BusyBox httpd utilise un fichier httpd.conf avec la directive:
#   /path:user:password
# pour activer l'authentification HTTP Basic sur un chemin.

# BusyBox httpd lit /etc/httpd.conf par défaut
AUTH_CONF="/etc/httpd.conf"
AUTH_REALM="webdav-sync"

# Configure l'authentification HTTP Basic si WEB_PASS est défini
setup_basic_auth() {
  user="${WEB_USER:-admin}"
  pass="${WEB_PASS:-}"

  # Pas de mot de passe = pas d'auth
  if [ -z "$pass" ]; then
    rm -f "$AUTH_CONF" 2>/dev/null || true
    return 0
  fi

  # Créer le fichier httpd.conf avec auth pour tout le site
  # Format BusyBox: /path:user:password (/ = racine du site)
  printf '/:%s:%s\n' "$user" "$pass" > "$AUTH_CONF"
  chmod 600 "$AUTH_CONF"
  log_info "Auth HTTP activée (user: $user)"
}

# Vérifie si l'auth est activée
is_auth_enabled() {
  [ -f "$AUTH_CONF" ]
}
