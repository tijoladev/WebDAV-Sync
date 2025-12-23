#!/bin/sh
# helpers/paths.sh — chemins, ports figés et utilitaires de base

# === Utilitaires de base ===

# Timestamp ISO 8601 avec timezone (ex: 2025-12-23T14:30:00+01:00)
_now() { date +"%Y-%m-%dT%H:%M:%S%z" | sed 's/\(..\)$/:\1/'; }

# === Chemins/constantes figés ===

LIB_DIR="/var/lib/webdav-sync"
RCLONE_CONF_FILE="${LIB_DIR}/rclone-internal.conf"
KSYNC_JSON_FILE="${LIB_DIR}/webdav-sync-internal.json"

WEB_ROOT="${LIB_DIR}/www"
STATUS_DIR="${WEB_ROOT}/status"

LOCAL_DIR="/webdav-sync/local-files"
LOG_DIR="/webdav-sync/logs"
LOG_PREFIX="webdav-sync"

REMOTE_MD5_FILE="${LIB_DIR}/creds.md5"
LAST_RUN_JSON="${LIB_DIR}/last_run.json"
PAUSE_FLAG_FILE="${LIB_DIR}/paused"

REMOTE_ALIAS="webdav"

# Adresse fixe de l’API RC d’rclone
RC_ADDR="127.0.0.1:5572"

# === Création stricte des dossiers ===

# Fonction interne simple, sans effet sur umask global
_create_dir_mode() {
  # $1 = chemin, $2 = mode (ex: 700 ou 755)
  mkdir -p -- "$1" 2>/dev/null || mkdir -p "$1"
  chmod "$2" "$1" 2>/dev/null || :
}

# Répertoires sensibles
_create_dir_mode "$LIB_DIR" 700

# Répertoires de travail et logs
_create_dir_mode "$WEB_ROOT" 755
_create_dir_mode "$STATUS_DIR" 755
_create_dir_mode "$LOCAL_DIR" 755
_create_dir_mode "$LOG_DIR" 755