#!/usr/bin/env bash
# Legt die gemeinsame und die Backend-Infrastruktur von RefCard 05 im AWS Academy Learner Lab an.
# Idempotent: bereits vorhandene Ressourcen werden wiederverwendet, das Skript kann mehrfach laufen.
#
#   ./infra/setup-aws.sh            # alles anlegen
#   ./infra/setup-aws.sh outputs    # nur die ermittelten Werte ausgeben
#
# Voraussetzung: gültige Learner-Lab-Zugangsdaten in ~/.aws/credentials (aws sts get-caller-identity).
set -euo pipefail

cd "$(dirname "$0")"
source ./config.sh

log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/voclabs"
TASK_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TASK_ROLE_NAME}"
BUCKET="${PROJECT}-employee-photos-${ACCOUNT_ID}-${AWS_REGION}"

VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId' --output text)
SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=availability-zone,Values=$(IFS=,; echo "${AZS[*]}")" \
  --query 'Subnets[].SubnetId' --output text)

sg_id() {
  aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=$1" \
    --query 'SecurityGroups[0].GroupId' --output text
}

ensure_sg() {
  local name=$1 description=$2 id
  id=$(sg_id "$name")
  if [[ "$id" == "None" ]]; then
    id=$(aws ec2 create-security-group --group-name "$name" --description "$description" \
      --vpc-id "$VPC_ID" --query GroupId --output text)
  fi
  echo "$id"
}

# Regel nur anlegen, wenn sie noch fehlt (authorize schlägt sonst mit InvalidPermission.Duplicate fehl).
allow_from_sg() {
  local target=$1 port=$2 source=$3
  aws ec2 authorize-security-group-ingress --group-id "$target" --protocol tcp --port "$port" \
    --source-group "$source" >/dev/null 2>&1 || true
}

allow_from_cidr() {
  local target=$1 port=$2 cidr=$3
  aws ec2 authorize-security-group-ingress --group-id "$target" --protocol tcp --port "$port" \
    --cidr "$cidr" >/dev/null 2>&1 || true
}

outputs() {
  local alb_dns db_host secret_arn
  alb_dns=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
    --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo "-")
  db_host=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" \
    --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo "-")
  secret_arn=$(aws secretsmanager describe-secret --secret-id "$DB_SECRET_NAME" \
    --query ARN --output text 2>/dev/null || echo "-")
  cat <<EOF

Account        : $ACCOUNT_ID
Region         : $AWS_REGION
ALB            : http://$alb_dns
RDS-Endpoint   : $db_host
DB-Secret-ARN  : $secret_arn
S3-Bucket      : $BUCKET
ECR (Backend)  : $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$BACKEND_ECR_REPO
EOF
}

if [[ "${1:-}" == "outputs" ]]; then
  outputs
  exit 0
fi

log "Security Groups"
SG_ALB=$(ensure_sg "$SG_ALB_NAME" "ALB: HTTP aus dem Internet")
SG_FRONTEND=$(ensure_sg "$SG_FRONTEND_NAME" "Frontend-Tasks: Port 80 nur vom ALB")
SG_BACKEND=$(ensure_sg "$SG_BACKEND_NAME" "Backend-Tasks: Port 8080 nur vom ALB")
SG_DB=$(ensure_sg "$SG_DB_NAME" "RDS MariaDB: Port 3306 nur von den Backend-Tasks")
allow_from_cidr "$SG_ALB" 80 0.0.0.0/0
allow_from_sg "$SG_FRONTEND" 80 "$SG_ALB"
allow_from_sg "$SG_BACKEND" 8080 "$SG_ALB"
allow_from_sg "$SG_DB" 3306 "$SG_BACKEND"
echo "alb=$SG_ALB frontend=$SG_FRONTEND backend=$SG_BACKEND db=$SG_DB"

log "RDS MariaDB ($DB_INSTANCE_ID)"
if ! aws rds describe-db-subnet-groups --db-subnet-group-name "$DB_SUBNET_GROUP" >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  aws rds create-db-subnet-group --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --db-subnet-group-description "Subnets fuer die RefCard-05-Datenbank" \
    --subnet-ids $SUBNET_IDS >/dev/null
fi

if ! aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" >/dev/null 2>&1; then
  # Das Passwort wird hier erzeugt und landet ausschliesslich in Secrets Manager - nie im Repo, nie im Terminal.
  DB_PASSWORD=$(openssl rand -hex 20)
  aws rds create-db-instance \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --db-instance-class db.t3.micro \
    --engine mariadb --engine-version "$DB_ENGINE_VERSION" \
    --allocated-storage 20 --storage-type gp2 --storage-encrypted \
    --db-name "$DB_NAME" \
    --master-username "$DB_USERNAME" --master-user-password "$DB_PASSWORD" \
    --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --vpc-security-group-ids "$SG_DB" \
    --no-publicly-accessible --no-multi-az \
    --backup-retention-period 1 \
    --tags Key=project,Value=refcard05 >/dev/null

  SECRET_STRING=$(jq -n --arg u "$DB_USERNAME" --arg p "$DB_PASSWORD" --arg n "$DB_NAME" \
    '{host: "pending", port: "3306", dbname: $n, username: $u, password: $p}')
  if aws secretsmanager describe-secret --secret-id "$DB_SECRET_NAME" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value --secret-id "$DB_SECRET_NAME" --secret-string "$SECRET_STRING" >/dev/null
  else
    aws secretsmanager create-secret --name "$DB_SECRET_NAME" \
      --description "RefCard 05: Verbindungsdaten des Backends zur RDS-MariaDB" \
      --secret-string "$SECRET_STRING" >/dev/null
  fi
  unset DB_PASSWORD SECRET_STRING
  echo "Instanz wird erstellt ..."
fi

log "S3-Bucket ($BUCKET)"
if ! aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  aws s3api create-bucket --bucket "$BUCKET" >/dev/null
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-encryption --bucket "$BUCKET" --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging 'TagSet=[{Key=project,Value=refcard05}]'

render_policy() {
  sed -e "s|__BUCKET__|$BUCKET|g" -e "s|__PREFIX__|$S3_PREFIX|g" \
    -e "s|__TASK_ROLE_ARN__|$TASK_ROLE_ARN|g" -e "s|__ADMIN_ROLE_ARN__|$ADMIN_ROLE_ARN|g" "$1"
}
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "$(render_policy s3-bucket-policy.json)"

log "IAM: Least-Privilege-Policy ($S3_POLICY_NAME)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${S3_POLICY_NAME}"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  aws iam create-policy --policy-name "$S3_POLICY_NAME" \
    --description "RefCard 05: Backend darf nur Mitarbeiterfotos im Bucket $BUCKET lesen/schreiben/loeschen" \
    --policy-document "$(render_policy iam-policy-s3-least-privilege.json)" >/dev/null
fi
echo "$POLICY_ARN"

log "ECR-Repository ($BACKEND_ECR_REPO)"
if ! aws ecr describe-repositories --repository-names "$BACKEND_ECR_REPO" >/dev/null 2>&1; then
  aws ecr create-repository --repository-name "$BACKEND_ECR_REPO" \
    --image-scanning-configuration scanOnPush=true >/dev/null
fi
aws ecr put-lifecycle-policy --repository-name "$BACKEND_ECR_REPO" \
  --lifecycle-policy-text file://ecr-lifecycle-policy.json >/dev/null

log "CloudWatch-Log-Group ($BACKEND_LOG_GROUP)"
aws logs create-log-group --log-group-name "$BACKEND_LOG_GROUP" 2>/dev/null || true
aws logs put-retention-policy --log-group-name "$BACKEND_LOG_GROUP" --retention-in-days 7

log "ECS-Cluster ($CLUSTER_NAME)"
if [[ $(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].status' --output text) != "ACTIVE" ]]; then
  aws ecs create-cluster --cluster-name "$CLUSTER_NAME" >/dev/null
fi

log "Application Load Balancer ($ALB_NAME)"
ALB_ARN=$(aws elbv2 describe-load-balancers --names "$ALB_NAME" \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)
if [[ -z "$ALB_ARN" || "$ALB_ARN" == "None" ]]; then
  # shellcheck disable=SC2086
  ALB_ARN=$(aws elbv2 create-load-balancer --name "$ALB_NAME" --type application --scheme internet-facing \
    --subnets $SUBNET_IDS --security-groups "$SG_ALB" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
fi

TG_BACKEND_ARN=$(aws elbv2 describe-target-groups --names "$TG_BACKEND_NAME" \
  --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)
if [[ -z "$TG_BACKEND_ARN" || "$TG_BACKEND_ARN" == "None" ]]; then
  TG_BACKEND_ARN=$(aws elbv2 create-target-group --name "$TG_BACKEND_NAME" \
    --protocol HTTP --port 8080 --vpc-id "$VPC_ID" --target-type ip \
    --health-check-path /actuator/health --health-check-interval-seconds 15 \
    --health-check-timeout-seconds 5 --healthy-threshold-count 2 --unhealthy-threshold-count 3 \
    --matcher HttpCode=200 \
    --query 'TargetGroups[0].TargetGroupArn' --output text)
fi
aws elbv2 modify-target-group-attributes --target-group-arn "$TG_BACKEND_ARN" \
  --attributes Key=deregistration_delay.timeout_seconds,Value=30 >/dev/null

LISTENER_ARN=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" \
  --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text)
if [[ -z "$LISTENER_ARN" || "$LISTENER_ARN" == "None" ]]; then
  # Default-Aktion ist bewusst ein 503: das Frontend-Repo haengt seine Target Group selbst als Default ein.
  LISTENER_ARN=$(aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" --protocol HTTP --port 80 \
    --default-actions 'Type=fixed-response,FixedResponseConfig={StatusCode=503,ContentType=text/plain,MessageBody=Frontend noch nicht deployt}' \
    --query 'Listeners[0].ListenerArn' --output text)
fi

BACKEND_PATHS='[{"Field":"path-pattern","Values":["/v1/*","/actuator/health","/actuator/info"]}]'
RULE_ARN=$(aws elbv2 describe-rules --listener-arn "$LISTENER_ARN" \
  --query "Rules[?Actions[0].TargetGroupArn=='$TG_BACKEND_ARN'].RuleArn | [0]" --output text)
if [[ -z "$RULE_ARN" || "$RULE_ARN" == "None" ]]; then
  aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 10 \
    --conditions "$BACKEND_PATHS" --actions "Type=forward,TargetGroupArn=$TG_BACKEND_ARN" >/dev/null
else
  aws elbv2 modify-rule --rule-arn "$RULE_ARN" --conditions "$BACKEND_PATHS" >/dev/null
fi

log "Warten auf RDS (dauert beim ersten Mal 5-10 Minuten)"
aws rds wait db-instance-available --db-instance-identifier "$DB_INSTANCE_ID"
DB_HOST=$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

# Host erst jetzt bekannt: im Secret nachtragen, ohne das Passwort je auszugeben.
CURRENT=$(aws secretsmanager get-secret-value --secret-id "$DB_SECRET_NAME" --query SecretString --output text)
if [[ $(jq -r .host <<<"$CURRENT") != "$DB_HOST" ]]; then
  aws secretsmanager put-secret-value --secret-id "$DB_SECRET_NAME" \
    --secret-string "$(jq --arg h "$DB_HOST" '.host = $h' <<<"$CURRENT")" >/dev/null
fi
unset CURRENT

log "ECS-Service ($BACKEND_SERVICE)"
if [[ $(aws ecs describe-services --cluster "$CLUSTER_NAME" --services "$BACKEND_SERVICE" \
  --query 'services[0].status' --output text) != "ACTIVE" ]]; then
  aws ecs register-task-definition --cli-input-json file://../task-definition.json >/dev/null
  # Start mit 0 Tasks: das erste Image liefert die Pipeline, sie setzt danach auch die Task-Anzahl.
  aws ecs create-service --cluster "$CLUSTER_NAME" --service-name "$BACKEND_SERVICE" \
    --task-definition "$BACKEND_FAMILY" --desired-count 0 --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_IDS//$'\t'/,}],securityGroups=[$SG_BACKEND],assignPublicIp=ENABLED}" \
    --load-balancers "targetGroupArn=$TG_BACKEND_ARN,containerName=$BACKEND_FAMILY,containerPort=8080" \
    --health-check-grace-period-seconds 120 \
    --deployment-configuration "deploymentCircuitBreaker={enable=true,rollback=true},minimumHealthyPercent=100,maximumPercent=200" \
    --tags key=project,value=refcard05 >/dev/null
fi

log "Fertig"
outputs
