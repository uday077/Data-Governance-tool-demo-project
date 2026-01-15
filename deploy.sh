#!/bin/bash

################################################################################
# Data Governance Tool - Deployment Script for EC2
# This script pulls the latest Docker image from ECR and deploys using Docker Compose
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit on pipe failure

################################################################################
# Configuration Variables
################################################################################

# AWS Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
ECR_REPOSITORY="${ECR_REPOSITORY:-data-governance-tool}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Application Configuration
APP_DIR="${APP_DIR:-/opt/data-governance-tool}"
ENV_FILE="${APP_DIR}/.env"
COMPOSE_FILE="${APP_DIR}/docker-compose.yml"

# Logging
LOG_FILE="${APP_DIR}/deploy.log"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo "[${TIMESTAMP}] [INFO] $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "[${TIMESTAMP}] [ERROR] $1" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    echo "[${TIMESTAMP}] [SUCCESS] $1" | tee -a "${LOG_FILE}"
}

################################################################################
# Validation Functions
################################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if running as root or with sudo
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo"
        exit 1
    fi
    
    # Check if AWS CLI is installed
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install it first."
        exit 1
    fi
    
    # Set docker-compose command (v1 vs v2)
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE="docker compose"
    else
        DOCKER_COMPOSE="docker-compose"
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running. Please start Docker."
        exit 1
    fi
    
    log_success "All prerequisites met"
}

################################################################################
# AWS and ECR Functions
################################################################################

get_aws_account_id() {
    if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
        log_info "Fetching AWS Account ID..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        
        if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
            log_error "Failed to retrieve AWS Account ID. Check AWS credentials."
            exit 1
        fi
        
        log_info "AWS Account ID: ${AWS_ACCOUNT_ID}"
    fi
}

ecr_login() {
    log_info "Logging in to Amazon ECR..."
    
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    
    # Login to ECR
    if aws ecr get-login-password --region "${AWS_REGION}" | \
       docker login --username AWS --password-stdin "${ECR_REGISTRY}"; then
        log_success "Successfully logged in to ECR"
    else
        log_error "Failed to login to ECR"
        exit 1
    fi
}

################################################################################
# Docker Image Functions
################################################################################

pull_latest_image() {
    log_info "Pulling latest Docker image from ECR..."
    
    IMAGE_URI="${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
    
    log_info "Pulling image: ${IMAGE_URI}"
    
    if docker pull "${IMAGE_URI}"; then
        log_success "Successfully pulled image ${IMAGE_URI}"
    else
        log_error "Failed to pull image ${IMAGE_URI}"
        exit 1
    fi
    
    # Export for docker-compose
    export ECR_REGISTRY="${ECR_REGISTRY}/${ECR_REPOSITORY}"
    export IMAGE_TAG="${IMAGE_TAG}"
}

cleanup_old_images() {
    log_info "Cleaning up old Docker images..."
    
    # Remove dangling images
    if docker image prune -f &> /dev/null; then
        log_success "Cleaned up dangling images"
    else
        log_info "No dangling images to clean up"
    fi
    
    # Remove old images of the same repository (keep latest 3)
    docker images "${ECR_REGISTRY}/${ECR_REPOSITORY}" --format "{{.ID}} {{.CreatedAt}}" | \
        sort -rk 2 | \
        awk 'NR>3 {print $1}' | \
        xargs -r docker rmi -f 2>/dev/null || true
}

################################################################################
# Application Deployment Functions
################################################################################

setup_application_directory() {
    log_info "Setting up application directory..."
    
    # Create app directory if it doesn't exist
    if [[ ! -d "${APP_DIR}" ]]; then
        mkdir -p "${APP_DIR}"
        log_info "Created application directory: ${APP_DIR}"
    fi
    
    cd "${APP_DIR}" || exit 1
}

create_env_file() {
    log_info "Creating/updating environment file..."
    
    # Create .env file with default values if it doesn't exist
    if [[ ! -f "${ENV_FILE}" ]]; then
        cat > "${ENV_FILE}" <<EOF
# Database Configuration
DB_PASSWORD=secure_password_$(openssl rand -hex 16)

# Redis Configuration
REDIS_PASSWORD=$(openssl rand -hex 16)

# Docker Image Configuration
ECR_REGISTRY=${ECR_REGISTRY}/${ECR_REPOSITORY}
IMAGE_TAG=${IMAGE_TAG}
EOF
        chmod 600 "${ENV_FILE}"
        log_success "Created new .env file"
    else
        # Update image configuration in existing .env
        sed -i "s|ECR_REGISTRY=.*|ECR_REGISTRY=${ECR_REGISTRY}/${ECR_REPOSITORY}|g" "${ENV_FILE}"
        sed -i "s|IMAGE_TAG=.*|IMAGE_TAG=${IMAGE_TAG}|g" "${ENV_FILE}"
        log_success "Updated .env file with new image configuration"
    fi
}

deploy_with_docker_compose() {
    log_info "Deploying application with Docker Compose..."
    
    # Check if compose file exists
    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        log_error "Docker Compose file not found at ${COMPOSE_FILE}"
        log_error "Please ensure docker-compose.yml and nginx.conf are in ${APP_DIR}"
        exit 1
    fi
    
    # Load environment variables
    set -a
    source "${ENV_FILE}"
    set +a
    
    # Pull all images defined in docker-compose
    log_info "Pulling all service images..."
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" pull
    
    # Stop and remove old containers
    log_info "Stopping old containers..."
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" down --remove-orphans
    
    # Start new containers
    log_info "Starting new containers..."
    if ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" up -d; then
        log_success "Application deployed successfully"
    else
        log_error "Failed to start containers"
        exit 1
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Wait for services to be healthy
    sleep 10
    
    # Check container status
    log_info "Container status:"
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" ps
    
    # Test health endpoint
    local max_attempts=12
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        log_info "Testing health endpoint (attempt ${attempt}/${max_attempts})..."
        
        if curl -f -s http://localhost/health > /dev/null; then
            log_success "Health check passed! Application is running."
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    log_error "Health check failed after ${max_attempts} attempts"
    log_info "Container logs:"
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" logs --tail=50
    exit 1
}

################################################################################
# Backup and Rollback Functions
################################################################################

backup_current_deployment() {
    log_info "Creating backup of current deployment..."
    
    BACKUP_DIR="${APP_DIR}/backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "${BACKUP_DIR}"
    
    # Backup current image info
    ${DOCKER_COMPOSE} -f "${COMPOSE_FILE}" images > "${BACKUP_DIR}/images.txt" 2>/dev/null || true
    
    # Backup environment file
    cp "${ENV_FILE}" "${BACKUP_DIR}/.env" 2>/dev/null || true
    
    log_success "Backup created at ${BACKUP_DIR}"
}

################################################################################
# Main Deployment Flow
################################################################################

main() {
    log_info "========================================="
    log_info "Starting Data Governance Tool Deployment"
    log_info "========================================="
    
    # Run all deployment steps
    check_prerequisites
    setup_application_directory
    get_aws_account_id
    ecr_login
    pull_latest_image
    backup_current_deployment
    create_env_file
    deploy_with_docker_compose
    verify_deployment
    cleanup_old_images
    
    log_success "========================================="
    log_success "Deployment completed successfully!"
    log_success "========================================="
    log_info "Access the application at: http://$(hostname -I | awk '{print $1}')"
    log_info "View logs with: cd ${APP_DIR} && ${DOCKER_COMPOSE} logs -f"
}

################################################################################
# Script Entry Point
################################################################################

# Execute main function
main "$@"