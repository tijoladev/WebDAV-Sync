#!/bin/sh
# helpers/web.sh — mini serveur web (busybox httpd)
# Dépend de: paths.sh (WEB_ROOT), logs.sh (log_info)
# Charge: auth.sh (setup_basic_auth, is_auth_enabled)

. /helpers/auth.sh

: "${WEB_ROOT:=/var/lib/webdav-sync/www}"
: "${HTTPD_BIN:=httpd}"
: "${WEB_PORT:=8080}"

_httpd_args_common() {
  mkdir -p "$WEB_ROOT"
  local extra=""
  # -r REALM active l'auth Basic (credentials dans /etc/httpd.conf)
  is_auth_enabled && extra="-r ${AUTH_REALM}"
  printf '%s ' -f -p "0.0.0.0:${WEB_PORT}" -h "$WEB_ROOT" $extra
}

# --- Modes de démarrage ---

start_web_background() {
  "$HTTPD_BIN" $(_httpd_args_common) -v >/dev/null 2>&1 &
  disown 2>/dev/null || true
}

is_web_running() {
  pgrep -x "$HTTPD_BIN" >/dev/null 2>&1
}

start_web_if_needed() {
  if is_web_running; then
    log_info "Serveur web déjà actif"
  else
    log_info "Démarrage du serveur web (port ${WEB_PORT}, root: ${WEB_ROOT})"
    setup_basic_auth
    install_cgi live
    install_cgi snapshot
    install_cgi control
    install_cgi logs
    start_web_background
  fi
}



# --- Installation générique d'un CGI ---
install_cgi() {
  name="$1"
  dir="${WEB_ROOT}/cgi-bin"
  path="${dir}/${name}.sh"

  mkdir -p "$dir"

  cat >"$path" <<EOF
#!/bin/sh
# CGI : passe par l’entrypoint pour charger la config et exécuter le mode "$name"
exec /entrypoint.sh $name
EOF

  chmod 755 "$path"
  log_info "CGI installé : $path"
}

cgi_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'  
}