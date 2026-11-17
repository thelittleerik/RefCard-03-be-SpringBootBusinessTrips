#!/usr/bin/env bash
# Löscht die gemeinsame und die Backend-Infrastruktur von RefCard 05 wieder (Gegenstück zu setup-aws.sh).
# Nach der Bewertung ausführen, damit das Learner Lab kein Guthaben mehr verbraucht.
#
#   ./infra/teardown-aws.sh
#
# Reihenfolge: zuerst infra/teardown-aws.sh im Frontend-Repo, dann dieses Skript.
# ACHTUNG: Die Datenbank und alle hochgeladenen Fotos werden unwiderruflich gelöscht (kein Snapshot).
set -euo pipefail

cd "$(dirname "$0")"
source ./config.sh

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="${PROJECT}-employee-photos-${ACCOUNT_ID}-${AWS_REGION}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${S3_POLICY_NAME}"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)

cat <<EOF
Folgende Ressourcen im Account $ACCOUNT_ID ($AWS_REGION) werden gelöscht:

  ECS-Service      $BACKEND_SERVICE
  ECS-Cluster      $CLUSTER_NAME
  Load Balancer    $ALB_NAME (inkl. Listener) und Target Group $TG_BACKEND_NAME
  RDS-Instanz      $DB_INSTANCE_ID  (alle Daten, ohne Snapshot)
  Secret           $DB_SECRET_NAME
  S3-Bucket        $BUCKET  (alle Fotos)
  IAM-Policy       $S3_POLICY_NAME
  ECR-Repository   $BACKEND_ECR_REPO  (alle Images)
  Log-Group        $BACKEND_LOG_GROUP
  Security Groups  $SG_DB_NAME, $SG_BACKEND_NAME, $SG_FRONTEND_NAME, $SG_ALB_NAME

EOF
read -r -p "Zum Bestätigen die Account-ID eingeben: " answer
[[ "$answer" == "$ACCOUNT_ID" ]] || { echo "Abgebrochen - nichts gelöscht."; exit 1; }

if [[ $(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "${PROJECT}-frontend-service" \
  --query 'services[0].status' --output text 2>/dev/null) == "ACTIVE" ]]; then
  echo "Der Frontend-Service läuft noch. Zuerst infra/teardown-aws.sh im Frontend-Repo ausführen." >&2
  exit 1
fi

log "ECS-Service und Cluster"
if [[ $(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$BACKEND_SERVICE" \
  --query 'services[0].status' --output text 2>/dev/null) == "ACTIVE" ]]; then
  aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$BACKEND_SERVICE" --force >/dev/null
  aws ecs wait services-inactive --cluster "$CLUSTER_NAME" --services "$BACKEND_SERVICE"
fi
aws ecs delete-cluster --cluster "$CLUSTER_NAME" >/dev/null 2>&1 || true

log "Load Balancer und Target Group"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [[ -n "$ALB_ARN" && "$ALB_ARN" != "None" ]]; then
  aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN"
  aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN"
fi
TG_ARN=$(aws elbv2 describe-target-groups --names "$TG_BACKEND_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [[ -n "$TG_ARN" && "$TG_ARN" != "None" ]]; then
  aws elbv2 delete-target-group --target-group-arn "$TG_ARN"
fi

log "RDS-Instanz (dauert einige Minuten)"
if aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" >/dev/null 2>&1; then
  aws rds delete-db-instance --db-instance-identifier "$DB_INSTANCE_ID" \
    --skip-final-snapshot --delete-automated-backups >/dev/null
  aws rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE_ID"
fi
aws rds delete-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP" 2>/dev/null || true

log "Secret"
aws secretsmanager delete-secret --secret-id "$DB_SECRET_NAME" --force-delete-without-recovery >/dev/null 2>&1 || true

log "S3-Bucket"
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  aws s3 rm "s3://$BUCKET" --recursive >/dev/null
  aws s3api delete-bucket --bucket "$BUCKET"
fi

log "IAM-Policy"
aws iam delete-policy --policy-arn "$POLICY_ARN" 2>/dev/null || true

log "ECR-Repository und Log-Group"
aws ecr delete-repository --repository-name "$BACKEND_ECR_REPO" --force >/dev/null 2>&1 || true
aws logs delete-log-group --log-group-name "$BACKEND_LOG_GROUP" 2>/dev/null || true

log "Security Groups"
# Reihenfolge wichtig: eine Gruppe lässt sich erst löschen, wenn keine andere mehr auf sie verweist.
# Die Netzwerk-Interfaces der gestoppten Tasks werden verzögert freigegeben, daher mit Wiederholung.
for name in "$SG_DB_NAME" "$SG_BACKEND_NAME" "$SG_FRONTEND_NAME" "$SG_ALB_NAME"; do
  id=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$name" \
    --query 'SecurityGroups[0].GroupId' --output text)
  [[ "$id" == "None" ]] && continue
  for ((i = 1; i <= 12; i++)); do
    if aws ec2 delete-security-group --group-id "$id" >/dev/null 2>&1; then
      echo "$name gelöscht"
      break
    fi
    (( i < 12 )) || echo "WARNUNG: $name ($id) konnte nicht gelöscht werden - wird noch verwendet. Später erneut ausführen." >&2
    sleep 10
  done
done

log "Fertig"
