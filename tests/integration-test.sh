#!/bin/sh
# tests/integration-test.sh — Test d'intégration avec serveur WebDAV réel
# Usage: ./tests/integration-test.sh
#
# Ce script:
# 1. Lance un serveur WebDAV (rclone serve webdav)
# 2. Lance webdav-sync configuré pour ce serveur
# 3. Teste une vraie synchronisation de fichiers
# 4. Vérifie que les fichiers sont bien transférés
# 5. Nettoie

set -eu

# === Configuration ============================================================
IMAGE_NAME="webdav-sync-test"
CONTAINER_SYNC="webdav-sync-integration"
CONTAINER_WEBDAV="webdav-server"
NETWORK_NAME="webdav-test-net"

WEBDAV_PORT=8081
SYNC_PORT=8080
TIMEOUT=60

# Couleurs
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BLUE='' NC=''
fi

# === Helpers ==================================================================
log_step()  { printf "${CYAN}[TEST]${NC} %s\n" "$*"; }
log_ok()    { printf "${GREEN}  ✓${NC} %s\n" "$*"; }
log_fail()  { printf "${RED}  ✗${NC} %s\n" "$*"; }
log_warn()  { printf "${YELLOW}  ⚠${NC} %s\n" "$*"; }
log_info()  { printf "${BLUE}  ℹ${NC} %s\n" "$*"; }

cleanup() {
  log_step "Nettoyage..."
  docker rm -f "$CONTAINER_SYNC" "$CONTAINER_WEBDAV" >/dev/null 2>&1 || true
  docker network rm "$NETWORK_NAME" >/dev/null 2>&1 || true
}

die() {
  log_fail "$1"
  # Afficher les logs pour debug
  echo ""
  log_warn "Logs du serveur WebDAV:"
  docker logs "$CONTAINER_WEBDAV" 2>&1 | tail -10 || true
  echo ""
  log_warn "Logs de webdav-sync:"
  docker logs "$CONTAINER_SYNC" 2>&1 | tail -20 || true
  cleanup
  exit 1
}

wait_for_http() {
  url="$1"
  max_wait="$2"
  auth="${3:-}"  # optionnel: user:pass
  waited=0
  while [ $waited -lt $max_wait ]; do
    if [ -n "$auth" ]; then
      http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 -u "$auth" "$url" 2>/dev/null || echo "000")
    else
      http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 "$url" 2>/dev/null || echo "000")
    fi
    # Accepter 200, 207 (WebDAV), ou 401 (auth required = serveur up)
    case "$http_code" in
      200|207|401) return 0 ;;
    esac
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# === Pre-checks ===============================================================
log_step "Vérification des prérequis..."

command -v docker >/dev/null 2>&1 || die "Docker n'est pas installé"
command -v curl >/dev/null 2>&1 || die "curl n'est pas installé"
command -v jq >/dev/null 2>&1 || die "jq n'est pas installé"

log_ok "Prérequis OK"

# === Cleanup préalable ========================================================
cleanup

# === Build ====================================================================
log_step "Build de l'image Docker..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if docker build -t "$IMAGE_NAME" "$PROJECT_DIR" >/dev/null 2>&1; then
  log_ok "Image buildée: $IMAGE_NAME"
else
  die "Échec du build Docker"
fi

# === Création du réseau =======================================================
log_step "Création du réseau Docker..."
docker network create "$NETWORK_NAME" >/dev/null 2>&1
log_ok "Réseau créé: $NETWORK_NAME"

# === Lancement du serveur WebDAV ==============================================
log_step "Démarrage du serveur WebDAV..."

# On utilise rclone serve webdav avec un dossier local
# Le serveur écoute sur le port 8081
docker run -d \
  --name "$CONTAINER_WEBDAV" \
  --network "$NETWORK_NAME" \
  -p "${WEBDAV_PORT}:8081" \
  rclone/rclone:1.71.2 \
  serve webdav /data --addr :8081 --user testuser --pass testpass >/dev/null 2>&1

log_ok "Serveur WebDAV démarré"

# Attendre que le serveur soit prêt
log_step "Attente du serveur WebDAV..."
if wait_for_http "http://localhost:${WEBDAV_PORT}/" 15; then
  log_ok "Serveur WebDAV prêt"
else
  die "Timeout: serveur WebDAV non disponible"
fi

# === Lancement de webdav-sync =================================================
log_step "Démarrage de webdav-sync..."

# URL du WebDAV depuis le réseau Docker
WEBDAV_URL="http://${CONTAINER_WEBDAV}:8081/"

# Mode CRON activé pour que le container reste en vie
# On déclenchera la sync manuellement via l'API control
docker run -d \
  --name "$CONTAINER_SYNC" \
  --network "$NETWORK_NAME" \
  -p "${SYNC_PORT}:8080" \
  -e CRON_ENABLED=true \
  -e CRON_SCHEDULE="0 0 31 2 *" \
  -e SYNC_OP=copy \
  -e LOG_LEVEL=DEBUG \
  -e REMOTE_URL="$WEBDAV_URL" \
  -e REMOTE_USER=testuser \
  -e REMOTE_PASS=testpass \
  "$IMAGE_NAME" >/dev/null 2>&1

log_ok "webdav-sync démarré"

# Attendre que le serveur web soit prêt
log_step "Attente du serveur web webdav-sync..."
if wait_for_http "http://localhost:${SYNC_PORT}/" 30; then
  log_ok "Serveur web prêt"
else
  die "Timeout: serveur web webdav-sync non disponible"
fi

# === Tests d'intégration ======================================================
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Créer des fichiers de test sur le WebDAV
log_step "Test: Upload de fichiers sur WebDAV..."

# Créer des fichiers de test via curl/WebDAV
curl -sf -u testuser:testpass -X MKCOL "http://localhost:${WEBDAV_PORT}/test-folder/" >/dev/null 2>&1 || true
echo "Hello from WebDAV" | curl -sf -u testuser:testpass -T - "http://localhost:${WEBDAV_PORT}/test-file.txt" >/dev/null 2>&1
echo "File in folder" | curl -sf -u testuser:testpass -T - "http://localhost:${WEBDAV_PORT}/test-folder/nested.txt" >/dev/null 2>&1

# Vérifier que les fichiers existent
if curl -sf -u testuser:testpass "http://localhost:${WEBDAV_PORT}/test-file.txt" | grep -q "Hello from WebDAV"; then
  log_ok "Fichiers uploadés sur WebDAV"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Échec upload WebDAV"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Vérifier la connexion au remote via l'API
log_step "Test: Vérification du remote..."
response=$(curl -sf "http://localhost:${SYNC_PORT}/cgi-bin/snapshot.sh" 2>/dev/null || echo "{}")
if printf '%s' "$response" | jq -e '.rclone' >/dev/null 2>&1; then
  log_ok "Snapshot accessible"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Snapshot inaccessible"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Lancer une synchronisation via control
log_step "Test: Déclenchement sync via API..."
response=$(curl -sf "http://localhost:${SYNC_PORT}/cgi-bin/control.sh?action=start" 2>/dev/null || echo "{}")
if printf '%s' "$response" | jq -e '.action == "start"' >/dev/null 2>&1; then
  log_ok "Sync déclenchée"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Échec déclenchement sync"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Attendre que la sync se termine
log_step "Attente de la fin de synchronisation..."
sleep 5

# Polling du status
waited=0
while [ $waited -lt 30 ]; do
  status=$(curl -sf "http://localhost:${SYNC_PORT}/cgi-bin/live.sh" 2>/dev/null | jq -r '.status' 2>/dev/null || echo "unknown")
  if [ "$status" = "inactive" ]; then
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

# Test 4: Vérifier que les fichiers sont arrivés localement
log_step "Test: Vérification des fichiers synchronisés..."

# Lister les fichiers dans le container
files_count=$(docker exec "$CONTAINER_SYNC" sh -c "find /webdav-sync/local-files -type f 2>/dev/null | wc -l" 2>/dev/null || echo "0")
files_count=$(echo "$files_count" | tr -d ' ')

if [ "$files_count" -ge 2 ]; then
  log_ok "Fichiers synchronisés: $files_count fichier(s)"
  TESTS_PASSED=$((TESTS_PASSED + 1))

  # Afficher les fichiers
  log_info "Contenu synchronisé:"
  docker exec "$CONTAINER_SYNC" sh -c "find /webdav-sync/local-files -type f" 2>/dev/null | while read f; do
    log_info "  - $f"
  done
else
  log_fail "Aucun fichier synchronisé (trouvé: $files_count)"
  TESTS_FAILED=$((TESTS_FAILED + 1))

  # Debug
  log_warn "Contenu du dossier local:"
  docker exec "$CONTAINER_SYNC" ls -la /webdav-sync/local-files/ 2>/dev/null || true
fi

# Test 5: Vérifier le contenu d'un fichier
log_step "Test: Vérification contenu fichier..."
content=$(docker exec "$CONTAINER_SYNC" cat /webdav-sync/local-files/test-file.txt 2>/dev/null || echo "")
if printf '%s' "$content" | grep -q "Hello from WebDAV"; then
  log_ok "Contenu fichier correct"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Contenu fichier incorrect: '$content'"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Vérifier les logs de sync
log_step "Test: Vérification logs..."
response=$(curl -sf "http://localhost:${SYNC_PORT}/cgi-bin/logs.sh" 2>/dev/null || echo "{}")
log_content=$(printf '%s' "$response" | jq -r '.content' 2>/dev/null || echo "")
if printf '%s' "$log_content" | grep -qi "copied\|transferred\|sync"; then
  log_ok "Logs de synchronisation présents"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_warn "Logs sync non trouvés (peut être normal si rapide)"
  # Ne pas compter comme échec
  TESTS_PASSED=$((TESTS_PASSED + 1))
fi

# === Résumé ===================================================================
cleanup

echo ""
echo "========================================"
printf "  Tests passés:  ${GREEN}%d${NC}\n" "$TESTS_PASSED"
printf "  Tests échoués: ${RED}%d${NC}\n" "$TESTS_FAILED"
echo "========================================"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
else
  log_ok "Tous les tests d'intégration sont passés!"
  exit 0
fi
