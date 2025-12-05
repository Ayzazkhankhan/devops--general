#!/bin/bash

set -e  # Exit on error
set -o pipefail

# --------------------------------------------------------
# CONFIGURATION
# --------------------------------------------------------
AWS_REGION="eu-central-1"
AWS_ACCOUNT_ID="730335654587"
ECR_REPO="730335654587.dkr.ecr.eu-central-1.amazonaws.com/xis-ai/prod"
DEPLOYMENT_NAME="master-app"
KUBECONFIG_PATH="$HOME/.kube/config"

# --------------------------------------------------------
# FUNCTIONS
# --------------------------------------------------------
log() {
    echo -e "\033[1;32m[INFO]\033[0m $1"
}

error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

# --------------------------------------------------------
# CHECK REQUIREMENTS
# --------------------------------------------------------
log "Checking tools..."

command -v aws >/dev/null 2>&1 || error "AWS CLI not installed"
command -v docker >/dev/null 2>&1 || error "Docker not installed"
command -v kubectl >/dev/null 2>&1 || error "Kubectl not installed"

log "All required tools exist."

# --------------------------------------------------------
# ECR LOGIN
# --------------------------------------------------------
log "Logging into AWS ECR..."

aws ecr get-login-password --region $AWS_REGION \
| docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
|| error "ECR login failed"

log "ECR login successful."

# --------------------------------------------------------
# TAG & PUSH DOCKER IMAGE
# --------------------------------------------------------
log "Tagging image..."

docker tag "$ECR_REPO:latest" "$ECR_REPO:latest" || error "Tagging failed"

log "Pushing image to ECR..."
docker push "$ECR_REPO:latest" || error "Push to ECR failed"

log "Image pushed successfully."

# --------------------------------------------------------
# KUBERNETES DEPLOYMENT UPDATE
# --------------------------------------------------------
export KUBECONFIG="$KUBECONFIG_PATH"

log "Updating Kubernetes deployment: $DEPLOYMENT_NAME"

kubectl set image deployment/$DEPLOYMENT_NAME \
    master-app="$ECR_REPO:latest" \
    || error "Failed to update deployment image"

log "Image updated. Verifying rollout..."

kubectl rollout status deployment/$DEPLOYMENT_NAME \
    || error "Rollout failed"

log "Deployment rollout completed successfully!"

echo ""
log "🎉 Deployment Finished Successfully!"
