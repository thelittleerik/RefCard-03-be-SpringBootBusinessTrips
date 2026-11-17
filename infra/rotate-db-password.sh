#!/usr/bin/env bash
# Setzt ein neues, zufälliges Passwort für die RDS-Instanz, trägt es in Secrets Manager nach
# und startet die Backend-Tasks neu, damit sie das neue Passwort beziehen.
# Das Passwort wird nie ausgegeben und nie als Datei abgelegt.
#
#   ./infra/rotate-db-password.sh
#
# Zwischen dem Wechsel in RDS und dem Neustart der Tasks können laufende Tasks keine neuen
# Datenbankverbindungen öffnen (bestehende Verbindungen bleiben gültig) - das Fenster dauert wenige Minuten.
set -euo pipefail

cd "$(dirname "$0")"
source ./config.sh

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

log "Neues Passwort in RDS setzen ($DB_INSTANCE_ID)"
NEW_PASSWORD=$(openssl rand -hex 20)
aws rds modify-db-instance --db-instance-identifier "$DB_INSTANCE_ID" \
  --master-user-password "$NEW_PASSWORD" --apply-immediately >/dev/null

for ((i = 1; i <= 60; i++)); do
  read -r status pending < <(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].[DBInstanceStatus,PendingModifiedValues.MasterUserPassword]' --output text)
  if [[ "$status" == "available" && "$pending" == "None" ]]; then
    break
  fi
  if (( i == 60 )); then
    echo "RDS hat das neue Passwort nach 10 Minuten nicht übernommen (Status: $status)." >&2
    echo "Secrets Manager wurde NICHT geändert. Skript erneut ausführen." >&2
    exit 1
  fi
  sleep 10
done
echo "übernommen"

log "Secrets Manager aktualisieren ($DB_SECRET_NAME)"
CURRENT=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_NAME" --query SecretString --output text)
aws secretsmanager put-secret-value --secret-id "$DB_SECRET_NAME" \
  --secret-string "$(jq --arg p "$NEW_PASSWORD" '.password = $p' <<<"$CURRENT")" >/dev/null
unset NEW_PASSWORD CURRENT
echo "aktualisiert"

log "Backend-Tasks neu starten ($BACKEND_SERVICE)"
aws ecs update-service --cluster "$CLUSTER_NAME" --service "$BACKEND_SERVICE" --force-new-deployment >/dev/null
aws ecs wait services-stable --cluster "$CLUSTER_NAME" --services "$BACKEND_SERVICE"
echo "Service stabil - alle Tasks verwenden das neue Passwort."
