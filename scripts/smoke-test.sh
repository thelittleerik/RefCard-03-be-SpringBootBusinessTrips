#!/usr/bin/env bash
# Prüft ein laufendes Backend von aussen: Health, ausgelieferte Version, Datenbank (RDS) und Bild-Storage (S3).
# Wird von der Pipeline nach jedem Deployment ausgeführt und funktioniert genauso gegen localhost.
#
#   ./scripts/smoke-test.sh <basis-url> [erwarteter-commit]
#   ./scripts/smoke-test.sh http://localhost:8080
set -euo pipefail

BASE_URL=${1:?Aufruf: smoke-test.sh <basis-url> [erwarteter-commit]}
BASE_URL=${BASE_URL%/}
EXPECTED_COMMIT=${2:-}
ATTEMPTS=${SMOKE_ATTEMPTS:-20}
WORK=$(mktemp -d)
EMPLOYEE_ID=""

fail() {
  echo "::error title=Smoke-Test fehlgeschlagen::$*"
  exit 1
}

cleanup() {
  if [[ -n "$EMPLOYEE_ID" ]]; then
    curl -s -o /dev/null -X DELETE "$BASE_URL/v1/employees/$EMPLOYEE_ID" || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

# Schreibt den Body nach $WORK/body und gibt nur den HTTP-Status aus ("000", wenn keine Verbindung zustande kommt).
request() {
  curl -s -o "$WORK/body" -w '%{http_code}' --max-time 10 "$@" || true
}

echo "1/4 Health: $BASE_URL/actuator/health"
for ((i = 1; i <= ATTEMPTS; i++)); do
  status=$(request "$BASE_URL/actuator/health")
  if [[ "$status" == "200" ]] && jq -e '.status == "UP"' "$WORK/body" >/dev/null 2>&1; then
    break
  fi
  (( i < ATTEMPTS )) || fail "/actuator/health meldet nach $ATTEMPTS Versuchen nicht UP (HTTP $status): $(head -c 300 "$WORK/body" 2>/dev/null)"
  sleep 5
done
echo "    UP"

echo "2/4 Version: $BASE_URL/actuator/info"
for ((i = 1; i <= ATTEMPTS; i++)); do
  status=$(request "$BASE_URL/actuator/info")
  commit=$(jq -r '.app.commit // empty' "$WORK/body" 2>/dev/null || true)
  version=$(jq -r '.app.version // empty' "$WORK/body" 2>/dev/null || true)
  if [[ "$status" == "200" && ( -z "$EXPECTED_COMMIT" || "$commit" == "$EXPECTED_COMMIT" ) ]]; then
    break
  fi
  (( i < ATTEMPTS )) || fail "Es läuft nicht der erwartete Stand. Erwartet Commit $EXPECTED_COMMIT, ausgeliefert wird '$commit' (HTTP $status). Das Deployment wurde vermutlich zurückgerollt - ECS-Service-Events prüfen."
  sleep 5
done
echo "    Version $version (Commit $commit)"

echo "3/4 Datenbank: $BASE_URL/v1/trips"
status=$(request "$BASE_URL/v1/trips")
[[ "$status" == "200" ]] || fail "/v1/trips antwortet mit HTTP $status statt 200 - Datenbankverbindung prüfen."
echo "    $(jq length "$WORK/body") Trips gelesen"

echo "4/4 Bild-Storage: Foto hochladen, laden, löschen"
status=$(request -X POST -H 'Content-Type: application/json' \
  -d '{"name":"Smoke Test","jobTitle":"Pipeline"}' "$BASE_URL/v1/employees")
[[ "$status" == "200" ]] || fail "Test-Mitarbeiter konnte nicht angelegt werden (HTTP $status)."
EMPLOYEE_ID=$(jq -r .id "$WORK/body")

# Kleinstes gültiges PNG (1x1 Pixel)
base64 -d > "$WORK/pixel.png" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='

status=$(request -X POST -F "file=@$WORK/pixel.png;type=image/png" "$BASE_URL/v1/employees/$EMPLOYEE_ID/photo")
[[ "$status" == "200" ]] || fail "Foto-Upload antwortet mit HTTP $status: $(head -c 300 "$WORK/body"). Bei 502 fehlen dem Task die Rechte auf den Bucket."

status=$(curl -s -o "$WORK/downloaded.png" -w '%{http_code}' --max-time 10 "$BASE_URL/v1/employees/$EMPLOYEE_ID/photo" || true)
[[ "$status" == "200" ]] || fail "Foto-Download antwortet mit HTTP $status."
cmp -s "$WORK/pixel.png" "$WORK/downloaded.png" || fail "Das geladene Foto unterscheidet sich vom hochgeladenen."

status=$(request -X DELETE "$BASE_URL/v1/employees/$EMPLOYEE_ID/photo")
[[ "$status" == "204" ]] || fail "Foto konnte nicht gelöscht werden (HTTP $status)."
echo "    Upload, Download und Löschen erfolgreich"

echo "Smoke-Test bestanden."
