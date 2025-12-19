#!/bin/bash
# AWS App Runner Deployment Script for LMACFY
# This script automates building, tagging, and pushing Docker image to AWS ECR

# Default values
REGION="us-east-1"
REPOSITORY="lmacfy"
IMAGE_TAG="latest"
DEPLOY=false

# Color codes
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        --repository)
            REPOSITORY="$2"
            shift 2
            ;;
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -d|--deploy)
            DEPLOY=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -r, --region REGION       AWS region (default: us-east-1)"
            echo "  --repository NAME         ECR repository name (default: lmacfy)"
            echo "  -t, --tag TAG            Docker image tag (default: latest)"
            echo "  -d, --deploy             Trigger App Runner deployment"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${CYAN}=====================================${NC}"
echo -e "${CYAN}LMACFY AWS Deployment Script${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""

# Check if AWS CLI is installed
echo -e "${YELLOW}Checking AWS CLI...${NC}"
if command -v aws &> /dev/null; then
    AWS_VERSION=$(aws --version)
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

# Get AWS Account ID
echo -e "${YELLOW}Getting AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>&1)
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ AWS Account ID: ${ACCOUNT_ID}${NC}"
else
    echo -e "${RED}✗ Failed to get AWS Account ID. Please run 'aws configure'${NC}"
    exit 1
fi

ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
FULL_IMAGE_NAME="${ECR_URI}/${REPOSITORY}:${IMAGE_TAG}"

echo ""
echo -e "${CYAN}Configuration:${NC}"
echo "  Region: ${REGION}"
echo "  Repository: ${REPOSITORY}"
echo "  Image Tag: ${IMAGE_TAG}"
echo "  Full Image: ${FULL_IMAGE_NAME}"
echo ""

# Authenticate Docker to ECR
echo -e "${YELLOW}Authenticating Docker to ECR...${NC}"
if aws ecr get-login-password --region "${REGION}" | docker login --username AWS --password-stdin "${ECR_URI}" 2>&1; then
    echo -e "${GREEN}✓ Docker authenticated to ECR${NC}"
else
    echo -e "${RED}✗ Failed to authenticate Docker to ECR${NC}"
    exit 1
fi

# Check if ECR repository exists, create if not
echo -e "${YELLOW}Checking ECR repository...${NC}"
if aws ecr describe-repositories --repository-names "${REPOSITORY}" --region "${REGION}" &> /dev/null; then
    echo -e "${GREEN}✓ ECR repository exists${NC}"
else
    echo -e "${YELLOW}Creating ECR repository...${NC}"
    if aws ecr create-repository --repository-name "${REPOSITORY}" --region "${REGION}" --image-scanning-configuration scanOnPush=true &> /dev/null; then
        echo -e "${GREEN}✓ ECR repository created${NC}"
    else
        echo -e "${RED}✗ Failed to create ECR repository${NC}"
        exit 1
    fi
fi

# Build Docker image
echo ""
echo -e "${YELLOW}Building Docker image...${NC}"
if docker build -t "${REPOSITORY}:${IMAGE_TAG}" .; then
    echo -e "${GREEN}✓ Docker image built successfully${NC}"
else
    echo -e "${RED}✗ Docker build failed${NC}"
    exit 1
fi

# Tag image for ECR
echo -e "${YELLOW}Tagging image for ECR...${NC}"
docker tag "${REPOSITORY}:${IMAGE_TAG}" "${FULL_IMAGE_NAME}"
echo -e "${GREEN}✓ Image tagged${NC}"

# Push to ECR
echo ""
echo -e "${YELLOW}Pushing image to ECR (this may take a few minutes)...${NC}"
if docker push "${FULL_IMAGE_NAME}"; then
    echo -e "${GREEN}✓ Image pushed to ECR successfully${NC}"
else
    echo -e "${RED}✗ Failed to push image to ECR${NC}"
    exit 1
fi

echo ""
echo -e "${CYAN}=====================================${NC}"
echo -e "${GREEN}Deployment to ECR Complete!${NC}"
echo -e "${CYAN}=====================================${NC}"
echo ""
echo -e "${CYAN}Image URI: ${FULL_IMAGE_NAME}${NC}"
echo ""

if [ "$DEPLOY" = true ]; then
    echo -e "${YELLOW}Triggering App Runner deployment...${NC}"
    echo ""
    echo -e "${YELLOW}To deploy to App Runner, you need the Service ARN.${NC}"
    echo -e "${YELLOW}Get it from AWS Console or run:${NC}"
    echo -e "${CYAN}  aws apprunner list-services --region ${REGION}${NC}"
    echo ""
    read -p "Enter App Runner Service ARN (or press Enter to skip): " SERVICE_ARN

    if [ -n "$SERVICE_ARN" ]; then
        if aws apprunner start-deployment --service-arn "$SERVICE_ARN" --region "${REGION}"; then
            echo -e "${GREEN}✓ Deployment triggered${NC}"
        else
            echo -e "${RED}✗ Failed to trigger deployment${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping App Runner deployment${NC}"
    fi
fi

echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo -e "${WHITE}1. Go to AWS App Runner Console: https://console.aws.amazon.com/apprunner/${NC}"
echo -e "${WHITE}2. Create or update your service to use: ${FULL_IMAGE_NAME}${NC}"
echo -e "${WHITE}3. Set environment variable: OPENAI_API_KEY${NC}"
echo ""
echo -e "${WHITE}Or use AWS CLI to deploy (see AWS.md for instructions)${NC}"
echo ""
