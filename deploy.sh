#!/usr/bin/env bash
# Ручне розгортання (CI/CD через OIDC неможливий через SCP акаунта, див. README):
# збирає образ із тегом = хеш коміту, пушить в ECR і застосовує Terraform.
# Додаткові аргументи передаються в terraform apply.
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "$(git status --porcelain -- app Dockerfile requirements.txt)" ]; then
  echo "Спершу закомітьте зміни в app/, Dockerfile, requirements.txt" >&2
  exit 1
fi

TAG=$(git rev-parse --short HEAD)
REPO=$(terraform -chdir=terraform output -raw ecr_repository_url)

if aws ecr describe-images --repository-name "${REPO##*/}" --image-ids imageTag="$TAG" >/dev/null 2>&1; then
  echo "Образ $TAG уже є в ECR"
else
  aws ecr get-login-password --region eu-north-1 |
    docker login --username AWS --password-stdin "${REPO%%/*}"
  docker build -t "$REPO:$TAG" .
  docker push "$REPO:$TAG"
fi

sed -i "s/^image_tag.*/image_tag   = \"$TAG\"/" terraform/terraform.tfvars
terraform -chdir=terraform apply "$@"
