#!/bin/sh
# tests/smoke-test.sh — Smoke test Docker pour webdav-sync
# Usage: ./tests/smoke-test.sh
#
# Ce script:
# 1. Build l'image Docker
# 2. Lance un container en mode test (sans vrais credentials)
# 3. Vérifie que les endpoints CGI répondent correctement
# 4. Nettoie

set -eu

# === Configuration ============================================================
IMAGE_NAME="webdav-sync-test"
CONTAINER_NAME="webdav-sync-smoke-test"
TEST_PORT=18080
TIMEOUT=30

# Couleurs (si terminal supporte)
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' NC=''
fi

# === Helpers ==================================================================
log_step() { printf "${CYAN}[TEST]${NC} %s\n" "$*"; }
log_ok()   { printf "${GREEN}  ✓${NC} %s\n" "$*"; }
log_fail() { printf "${RED}  ✗${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}  ⚠${NC} %s\n" "$*"; }

cleanup() {
  log_step "Nettoyage..."
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

die() {
  log_fail "$1"
  cleanup
  exit 1
}

# Vérifie qu'une réponse est du JSON valide
check_json() {
  if printf '%s' "$1" | jq -e . >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Vérifie qu'un champ existe dans le JSON
check_field() {
  json="$1"
  field="$2"
  if printf '%s' "$json" | jq -e "$field" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Requête HTTP avec timeout
http_get() {
  curl -sf --max-time 5 "http://localhost:${TEST_PORT}$1" 2>/dev/null || echo ""
}

# === Pre-checks ===============================================================
log_step "Vérification des prérequis..."

command -v docker >/dev/null 2>&1 || die "Docker n'est pas installé"
command -v curl >/dev/null 2>&1 || die "curl n'est pas installé"
command -v jq >/dev/null 2>&1 || die "jq n'est pas installé"

log_ok "Prérequis OK (docker, curl, jq)"

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

# === Run container ============================================================
log_step "Démarrage du container..."

# On lance en mode CRON activé - le container reste en vie pour attendre le cron
# Les endpoints web sont disponibles immédiatement
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${TEST_PORT}:8080" \
  -e CRON_ENABLED=true \
  -e CRON_SCHEDULE="0 0 31 2 *" \
  -e REMOTE_URL=http://fake-webdav.local/ \
  -e REMOTE_USER=test@example.com \
  -e REMOTE_PASS=fake_password \
  "$IMAGE_NAME" >/dev/null 2>&1 || die "Échec du démarrage container"

log_ok "Container démarré: $CONTAINER_NAME"

# === Attendre que le serveur soit prêt ========================================
log_step "Attente du serveur web (max ${TIMEOUT}s)..."

waited=0
while [ $waited -lt $TIMEOUT ]; do
  if curl -sf --max-time 1 "http://localhost:${TEST_PORT}/" >/dev/null 2>&1; then
    log_ok "Serveur web prêt après ${waited}s"
    break
  fi
  sleep 1
  waited=$((waited + 1))
done

if [ $waited -ge $TIMEOUT ]; then
  docker logs "$CONTAINER_NAME" 2>&1 | tail -20
  die "Timeout: serveur web non disponible après ${TIMEOUT}s"
fi

# === Tests des endpoints ======================================================
TESTS_PASSED=0
TESTS_FAILED=0

test_endpoint() {
  name="$1"
  path="$2"
  required_fields="$3"

  log_step "Test: $name"

  response=$(http_get "$path")

  if [ -z "$response" ]; then
    log_fail "$name - Pas de réponse"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi

  if ! check_json "$response"; then
    log_fail "$name - Réponse non-JSON: $(echo "$response" | head -c 100)"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi

  # Vérifie les champs requis
  for field in $required_fields; do
    if ! check_field "$response" "$field"; then
      log_fail "$name - Champ manquant: $field"
      TESTS_FAILED=$((TESTS_FAILED + 1))
      return 1
    fi
  done

  log_ok "$name"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  return 0
}

# Test 1: /cgi-bin/live.sh
test_endpoint "CGI live" "/cgi-bin/live.sh" ".status .extracted_at"

# Test 2: /cgi-bin/snapshot.sh
test_endpoint "CGI snapshot" "/cgi-bin/snapshot.sh" ".extracted_at .rclone .local"

# Test 3: /cgi-bin/logs.sh
test_endpoint "CGI logs" "/cgi-bin/logs.sh" ".extracted_at .content .available_dates"

# Test 4: /cgi-bin/logs.sh avec paramètres
test_endpoint "CGI logs (params)" "/cgi-bin/logs.sh?lines=50&date=today" ".lines_requested"

# Test 5: /cgi-bin/control.sh?action=pause (devrait retourner ok:false car pas de sync)
log_step "Test: CGI control (pause sans sync)"
response=$(http_get "/cgi-bin/control.sh?action=pause")
if check_json "$response" && check_field "$response" ".action"; then
  # ok:false est attendu car pas de sync en cours
  log_ok "CGI control (pause) - réponse correcte"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "CGI control (pause)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Action inconnue
log_step "Test: CGI control (action invalide)"
response=$(http_get "/cgi-bin/control.sh?action=invalid")
if check_json "$response" && check_field "$response" ".error"; then
  log_ok "CGI control (invalid) - erreur correcte"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "CGI control (invalid)"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 7: Page HTML principale
log_step "Test: Page index.html"
html=$(http_get "/")
if printf '%s' "$html" | grep -qi "webdav-sync"; then
  log_ok "Page index.html"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Page index.html - contenu inattendu"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# === Tests avec authentification ==============================================
log_step "Test: Authentification HTTP Basic..."

# Arrêter le container actuel
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1

# Relancer avec auth
docker run -d \
  --name "$CONTAINER_NAME" \
  -p "${TEST_PORT}:8080" \
  -e CRON_ENABLED=true \
  -e CRON_SCHEDULE="0 0 31 2 *" \
  -e REMOTE_URL=http://fake-webdav.local/ \
  -e REMOTE_USER=test@example.com \
  -e REMOTE_PASS=fake_password \
  -e WEB_PASS=secret123 \
  "$IMAGE_NAME" >/dev/null 2>&1

# Attendre
sleep 3

# Sans auth -> devrait échouer (401)
http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${TEST_PORT}/cgi-bin/live.sh" 2>/dev/null || echo "000")
if [ "$http_code" = "401" ]; then
  log_ok "Auth requise (401 sans credentials)"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_warn "Auth: code $http_code au lieu de 401"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Avec auth -> devrait réussir
response=$(curl -sf --max-time 5 -u "admin:secret123" "http://localhost:${TEST_PORT}/cgi-bin/live.sh" 2>/dev/null || echo "")
if check_json "$response" && check_field "$response" ".status"; then
  log_ok "Auth acceptée avec credentials corrects"
  TESTS_PASSED=$((TESTS_PASSED + 1))
else
  log_fail "Auth: échec avec credentials corrects"
  TESTS_FAILED=$((TESTS_FAILED + 1))
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
  log_ok "Tous les tests sont passés!"
  exit 0
fi
