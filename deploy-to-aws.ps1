# AWS App Runner Deployment Script for LMACFY
# This script automates building, tagging, and pushing Docker image to AWS ECR

param(
    [string]$Region = "us-east-1",
    [string]$Repository = "lmacfy",
    [string]$ImageTag = "latest",
    [switch]$Deploy
)

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "LMACFY AWS Deployment Script" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

# Check if AWS CLI is installed
Write-Host "Checking AWS CLI..." -ForegroundColor Yellow
try {
    $awsVersion = aws --version
    Write-Host "✓ AWS CLI found: $awsVersion" -ForegroundColor Green
} catch {
    Write-Host "✗ AWS CLI not found. Please install it first." -ForegroundColor Red
    exit 1
}

# Check if Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    docker ps > $null 2>&1
    Write-Host "✓ Docker is running" -ForegroundColor Green
} catch {
    Write-Host "✗ Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Get AWS Account ID
Write-Host "Getting AWS Account ID..." -ForegroundColor Yellow
try {
    $AccountId = aws sts get-caller-identity --query Account --output text
    Write-Host "✓ AWS Account ID: $AccountId" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to get AWS Account ID. Please run 'aws configure'" -ForegroundColor Red
    exit 1
}

$EcrUri = "$AccountId.dkr.ecr.$Region.amazonaws.com"
$FullImageName = "$EcrUri/$Repository`:$ImageTag"

Write-Host ""
Write-Host "Configuration:" -ForegroundColor Cyan
Write-Host "  Region: $Region"
Write-Host "  Repository: $Repository"
Write-Host "  Image Tag: $ImageTag"
Write-Host "  Full Image: $FullImageName"
Write-Host ""

# Authenticate Docker to ECR
Write-Host "Authenticating Docker to ECR..." -ForegroundColor Yellow
try {
    aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $EcrUri
    Write-Host "✓ Docker authenticated to ECR" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to authenticate Docker to ECR" -ForegroundColor Red
    exit 1
}

# Check if ECR repository exists, create if not
Write-Host "Checking ECR repository..." -ForegroundColor Yellow
$repoExists = aws ecr describe-repositories --repository-names $Repository --region $Region 2>$null
if (-not $repoExists) {
    Write-Host "Creating ECR repository..." -ForegroundColor Yellow
    aws ecr create-repository --repository-name $Repository --region $Region --image-scanning-configuration scanOnPush=true
    Write-Host "✓ ECR repository created" -ForegroundColor Green
} else {
    Write-Host "✓ ECR repository exists" -ForegroundColor Green
}

# Build Docker image
Write-Host ""
Write-Host "Building Docker image..." -ForegroundColor Yellow
docker build -t "$Repository`:$ImageTag" .
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host "✗ Docker build failed" -ForegroundColor Red
    exit 1
}

# Tag image for ECR
Write-Host "Tagging image for ECR..." -ForegroundColor Yellow
docker tag "$Repository`:$ImageTag" $FullImageName
Write-Host "✓ Image tagged" -ForegroundColor Green

# Push to ECR
Write-Host ""
Write-Host "Pushing image to ECR (this may take a few minutes)..." -ForegroundColor Yellow
docker push $FullImageName
if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Image pushed to ECR successfully" -ForegroundColor Green
} else {
    Write-Host "✗ Failed to push image to ECR" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "Deployment to ECR Complete!" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Image URI: $FullImageName" -ForegroundColor Cyan
Write-Host ""

if ($Deploy) {
    Write-Host "Triggering App Runner deployment..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To deploy to App Runner, you need the Service ARN." -ForegroundColor Yellow
    Write-Host "Get it from AWS Console or run:" -ForegroundColor Yellow
    Write-Host "  aws apprunner list-services --region $Region" -ForegroundColor Cyan
    Write-Host ""
    $ServiceArn = Read-Host "Enter App Runner Service ARN (or press Enter to skip)"

    if ($ServiceArn) {
        aws apprunner start-deployment --service-arn $ServiceArn --region $Region
        Write-Host "✓ Deployment triggered" -ForegroundColor Green
    } else {
        Write-Host "Skipping App Runner deployment" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "1. Go to AWS App Runner Console: https://console.aws.amazon.com/apprunner/" -ForegroundColor White
Write-Host "2. Create or update your service to use: $FullImageName" -ForegroundColor White
Write-Host "3. Set environment variable: OPENAI_API_KEY" -ForegroundColor White
Write-Host ""
Write-Host "Or use AWS CLI to deploy (see AWS.md for instructions)" -ForegroundColor White
Write-Host ""
