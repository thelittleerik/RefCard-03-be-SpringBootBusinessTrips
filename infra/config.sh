#!/usr/bin/env bash
# Gemeinsame Namen für alle AWS-Ressourcen von RefCard 05.
# Wird von setup-aws.sh / teardown-aws.sh (Backend-Repo) und vom Frontend-Repo (infra/) verwendet.
# Enthält bewusst keine Zugangsdaten und keine Account-ID.

export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_PAGER=""

PROJECT="biztrips"

# Netzwerk
SG_ALB_NAME="${PROJECT}-alb-sg"
SG_FRONTEND_NAME="${PROJECT}-frontend-sg"
SG_BACKEND_NAME="${PROJECT}-backend-sg"
SG_DB_NAME="${PROJECT}-db-sg"
AZS=("us-east-1a" "us-east-1b" "us-east-1c")

# Load Balancer
ALB_NAME="${PROJECT}-alb"
TG_BACKEND_NAME="${PROJECT}-backend-tg"

# ECS / ECR
CLUSTER_NAME="${PROJECT}-cluster"
BACKEND_ECR_REPO="${PROJECT}-backend"
BACKEND_SERVICE="${PROJECT}-backend-service"
BACKEND_FAMILY="${PROJECT}-backend"
BACKEND_LOG_GROUP="/ecs/${PROJECT}-backend"
TASK_ROLE_NAME="LabRole"

# RDS
DB_INSTANCE_ID="${PROJECT}-db"
DB_SUBNET_GROUP="${PROJECT}-db-subnets"
DB_NAME="db_biztrips"
DB_USERNAME="biztrips"
DB_ENGINE_VERSION="10.11"
DB_SECRET_NAME="${PROJECT}/backend/db"

# S3
S3_PREFIX="employee-photos/"
S3_POLICY_NAME="${PROJECT}-backend-s3-least-privilege"
