#!/bin/bash
# AWS App Runner Deployment Script for LMACFY
# Builds an amd64 image (for App Runner), tags it, and pushes to ECR.
# Optionally triggers an App Runner deployment.

set -euo pipefail

# Default values
REGION="us-east-1"
REPOSITORY="lmacfy"
IMAGE_TAG=""
PUSH_LATEST=false
DEPLOY=false
SERVICE_ARN=""           # Optional: set this once to avoid passing --service-arn every time
PLATFORM="linux/amd64"   # App Runner expects amd64

# Color codes
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -r, --region REGION        AWS region (default: us-east-1)"
  echo "  --repository NAME          ECR repository name (default: lmacfy)"
  echo "  -t, --tag TAG              Docker image tag (default: <git short hash>)"
  echo "  --latest                   Also tag/push the image as :latest"
  echo "  -d, --deploy               Trigger App Runner deployment"
  echo "  --service-arn ARN          App Runner Service ARN (recommended with --deploy)"
  echo "  --platform PLATFORM        Build platform (default: linux/amd64)"
  echo "  -h, --help                 Show this help message"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--region)
      REGION="$2"; shift 2 ;;
    --repository)
      REPOSITORY="$2"; shift 2 ;;
    -t|--tag)
      IMAGE_TAG="$2"; shift 2 ;;
    --latest)
      PUSH_LATEST=true; shift ;;
    -d|--deploy)
      DEPLOY=true; shift ;;
    --service-arn)
      SERVICE_ARN="$2"; shift 2 ;;
    --platform)
      PLATFORM="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      exit 1 ;;
  esac
done

echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}LMACFY AWS Deployment Script${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

if [ ! -d .git ]; then
  echo -e "${RED}✗ .git not found. Run this script from the repo root.${NC}"
  exit 1
fi

# Check if AWS CLI is installed
echo -e "${YELLOW}Checking AWS CLI...${NC}"
if command -v aws &> /dev/null; then
  AWS_VERSION=$(aws --version 2>&1 || true)
  echo -e "${GREEN}✓ AWS CLI found: ${AWS_VERSION}${NC}"
else
  echo -e "${RED}✗ AWS CLI not found. Please install it first.${NC}"
  exit 1
fi

# Check if Docker is running
echo -e "${YELLOW}Checking Docker...${NC}"
if docker ps &> /dev/null; then
  echo -e "${GREEN}✓ Docker is running${NC}"
else
  echo -e "${RED}✗ Docker is not running. Please start Docker.${NC}"
  exit 1
fi

# Check for buildx
echo -e "${YELLOW}Checking Docker buildx...${NC}"
if docker buildx version &> /dev/null; then
  echo -e "${GREEN}✓ Docker buildx available${NC}"
else
  echo -e "${RED}✗ Docker buildx not available. Please upgrade Docker / enable buildx.${NC}"
  exit 1
fi

# Get AWS Account ID
echo -e "${YELLOW}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>&1)
echo -e "${GREEN}✓ AWS Account ID: ${ACCOUNT_ID}${NC}"

# Determine git revision (APP_REV) and default image tag
GIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "dev")
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="$GIT_HASH"
fi
APP_REV="$GIT_HASH"

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
FULL_IMAGE_NAME="${ECR_URI}/${REPOSITORY}:${IMAGE_TAG}"
LATEST_IMAGE_NAME="${ECR_URI}/${REPOSITORY}:latest"

echo ""
echo -e "${CYAN}Configuration:${NC}"
echo "  Region: ${REGION}"
echo "  Repository: ${REPOSITORY}"
echo "  Platform: ${PLATFORM}"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Full Image: ${FULL_IMAGE_NAME}"
if [ "$PUSH_LATEST" = true ]; then
  echo "  Also push: ${LATEST_IMAGE_NAME}"
fi
echo "  Git Rev (APP_REV): ${APP_REV}"
if [ "$DEPLOY" = true ]; then
  echo "  Deploy: true"
  echo "  Service ARN: ${SERVICE_ARN:-<not set>}"
fi
echo ""

# Authenticate Docker to ECR
echo -e "${YELLOW}Authenticating Docker to ECR...${NC}"
aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URI}" >/dev/null
echo -e "${GREEN}✓ Docker authenticated to ECR${NC}"

# Check if ECR repository exists, create if not
echo -e "${YELLOW}Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names "${REPOSITORY}" --region "${REGION}" &> /dev/null; then
  echo -e "${GREEN}✓ ECR repository exists${NC}"
else
  echo -e "${YELLOW}Creating ECR repository...${NC}"
  aws ecr create-repository --repository-name "${REPOSITORY}" --region "${REGION}" \
    --image-scanning-configuration scanOnPush=true >/dev/null
  echo -e "${GREEN}✓ ECR repository created${NC}"
fi

# Ensure a buildx builder exists and is bootstrapped (safe to repeat)
echo -e "${YELLOW}Preparing buildx builder...${NC}"
docker buildx create --use --name lmacfy-builder >/dev/null 2>&1 || docker buildx use lmacfy-builder
docker buildx inspect --bootstrap >/dev/null
echo -e "${GREEN}✓ buildx builder ready${NC}"

# Build & push (amd64) directly to ECR
echo ""
echo -e "${YELLOW}Building & pushing Docker image (${PLATFORM})...${NC}"

TAGS=(-t "${FULL_IMAGE_NAME}")
if [ "$PUSH_LATEST" = true ]; then
  TAGS+=(-t "${LATEST_IMAGE_NAME}")
fi

docker buildx build \
  --platform "${PLATFORM}" \
  --build-arg APP_REV="${APP_REV}" \
  "${TAGS[@]}" \
  --push \
  .

echo -e "${GREEN}✓ Image build & push complete${NC}"

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${GREEN}Deployment to ECR Complete!${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""
echo -e "${CYAN}Image URI: ${FULL_IMAGE_NAME}${NC}"
if [ "$PUSH_LATEST" = true ]; then
  echo -e "${CYAN}Latest URI: ${LATEST_IMAGE_NAME}${NC}"
fi
echo ""

# Optionally trigger App Runner deployment
if [ "$DEPLOY" = true ]; then
  if [ -z "${SERVICE_ARN}" ]; then
    echo -e "${RED}✗ --deploy was set but --service-arn is missing.${NC}"
    echo -e "${YELLOW}  Tip: run:${NC}"
    echo -e "${CYAN}  aws apprunner list-services --region ${REGION}${NC}"
    exit 1
  fi

  echo -e "${YELLOW}Triggering App Runner deployment...${NC}"
  aws apprunner start-deployment --service-arn "${SERVICE_ARN}" --region "${REGION}" >/dev/null
  echo -e "${GREEN}✓ Deployment triggered${NC}"
fi

echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "${WHITE}1. Verify health:${NC}"
echo -e "${CYAN}   curl -i \"https://<your-service-url>/healthz?_=\$(date +%s)\"${NC}"
echo -e "${WHITE}2. Confirm App Runner uses the expected image tag/digest in the console.${NC}"
echo ""
