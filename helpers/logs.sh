#!/bin/sh
# helpers/logs.sh — gestion centralisée des logs et messages
# Dépend de: paths.sh (_now, LOG_DIR, LOG_PREFIX)

# Retourne le chemin du fichier log du jour
log_file_helper() {
  [ "$NO_LOG" = true ] && return 0
  file="${LOG_DIR}/${LOG_PREFIX}-$(date +%Y-%m-%d).log"
  [ ! -f "$file" ] && { mkdir -p "$LOG_DIR"; : >"$file"; chown "${PUID:-0}:${PGID:-0}" "$file" 2>/dev/null || true; }
  case "$1" in
    path) printf '%s' "$file" ;;
    arg)  printf '--log-file %s --log-level %s' "$file" "${LOG_LEVEL:-INFO}" ;;
  esac
}

# rotate_logs -> supprime les logs plus vieux que LOG_MAX_DAYS
rotate_logs() {
  [ "$NO_LOG" = true ] && return 0
  find "$LOG_DIR" -type f -name "${LOG_PREFIX}-*.log" -mtime +"${LOG_MAX_DAYS:-5}" -delete 2>/dev/null || :
}

# log_info MSG -> affiche un message formaté sur stdout + fichier log
log_info() {
  msg="[$(_now)] [INFO] $*"
  printf '%s\n' "$msg"
  [ "$NO_LOG" != true ] && printf '%s\n' "$msg" >> "$(log_file_helper path)" 2>/dev/null || true
}

# log_warn MSG -> affiche un avertissement sur stdout + fichier log
log_warn() {
  msg="[$(_now)] [WARN] $*"
  printf '%s\n' "$msg"
  [ "$NO_LOG" != true ] && printf '%s\n' "$msg" >> "$(log_file_helper path)" 2>/dev/null || true
}

# log_error MSG -> affiche un message formaté sur stderr + fichier log
log_error() {
  msg="[$(_now)] [ERROR] $*"
  printf '%s\n' "$msg" >&2
  [ "$NO_LOG" != true ] && printf '%s\n' "$msg" >> "$(log_file_helper path)" 2>/dev/null || true
}

# log_banner -> affiche un entête avant l'exécution du job (stdout + fichier)
log_banner() {
  _banner() {
    echo "============================================================"
    echo ">> RCLONE ${SYNC_OP} vers ${LOCAL_DIR}"
    [ -n "$SYNC_FLAGS" ] && echo "   Flags : $SYNC_FLAGS"
    echo "   Démarré à : $(date '+%F %T %Z')"
    echo "============================================================"
  }
  _banner
  [ "$NO_LOG" != true ] && _banner >> "$(log_file_helper path)" 2>/dev/null || true
}

# logs_collect -> retourne les dernières lignes de logs en JSON (pour CGI)
# Usage: logs_collect [lines] [file]
#   lines: nombre de lignes (défaut: 100)
#   file: "today" ou "YYYY-MM-DD" (défaut: today)
logs_collect() {
  lines="${1:-100}"
  target="${2:-today}"

  # Déterminer le fichier
  if [ "$target" = "today" ]; then
    file="${LOG_DIR}/${LOG_PREFIX}-$(date +%Y-%m-%d).log"
  else
    file="${LOG_DIR}/${LOG_PREFIX}-${target}.log"
  fi

  # Lister les fichiers de logs disponibles
  available="[]"
  if [ -d "$LOG_DIR" ]; then
    available=$(ls -1 "$LOG_DIR"/${LOG_PREFIX}-*.log 2>/dev/null | sed 's|.*/||;s|\.log$||;s|^'"${LOG_PREFIX}-"'||' | jq -R . | jq -s . 2>/dev/null || echo '[]')
  fi

  # Lire les dernières lignes
  if [ -f "$file" ]; then
    content=$(tail -n "$lines" "$file" 2>/dev/null | jq -Rs . 2>/dev/null || echo '""')
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    total_lines=$(wc -l < "$file" 2>/dev/null || echo 0)
  else
    content='""'
    size=0
    total_lines=0
  fi

  jq -n \
    --arg ts "$(_now)" \
    --arg file "$(basename "$file" 2>/dev/null || echo "")" \
    --argjson content "$content" \
    --argjson lines "$lines" \
    --argjson size "$size" \
    --argjson total "$total_lines" \
    --argjson available "$available" \
    '{
      extracted_at: $ts,
      file: $file,
      lines_requested: $lines,
      total_lines: $total,
      size_bytes: $size,
      available_dates: $available,
      content: $content
    }'
}