  # Data Governance Tool - DevOps Demo Project

A production-ready Data Governance Tool demonstrating a complete AWS DevOps workflow with Docker, ECR, CodeBuild, and EC2 deployment.

## 📋 Architecture Overview

```
GitHub/CodeCommit → AWS CodeBuild → Amazon ECR → EC2 Instance
                        ↓
                  Build & Push Image
                        ↓
                   Deploy Script
                        ↓
              Docker Compose (4 Containers)
              ├── App (Node.js)
              ├── PostgreSQL
              ├── Redis
              └── Nginx (Reverse Proxy)
```

## 🚀 Features

- **RESTful API** for data asset management
- **PostgreSQL** for persistent storage
- **Redis** for caching
- **Nginx** as reverse proxy with load balancing
- **Multi-stage Docker builds** for optimized images
- **Health checks** for all services
- **Automated CI/CD** with AWS CodeBuild
- **Production-ready** with security best practices

## 📦 Project Structure

```
.
├── app.js                 # Main Node.js application
├── package.json           # Node.js dependencies
├── Dockerfile             # Multi-stage Docker build
├── docker-compose.yml     # Multi-container orchestration
├── nginx.conf             # Nginx reverse proxy config
├── buildspec.yml          # AWS CodeBuild specification
├── deploy.sh              # EC2 deployment script
├── .env.example           # Environment variables template
└── README.md              # This file
```

## 🛠️ Prerequisites

### For Local Development
- Docker (20.10+)
- Docker Compose (2.0+)
- Node.js (18+) - optional, for local testing

### For AWS Deployment
- AWS Account with appropriate permissions
- AWS CLI configured
- EC2 instance with Docker and Docker Compose installed
- IAM role with ECR and CodeBuild permissions

## 🏃 Quick Start

### 1. Local Development

```bash
# Clone the repository
git clone <repository-url>
cd data-governance-tool

# Create environment file
cp .env.example .env

# Build and run with Docker Compose
docker-compose up --build -d

# View logs
docker-compose logs -f

# Test the application
curl http://localhost/health
curl http://localhost/api/assets
```

### 2. Create Sample Data

```bash
# Create a test asset
curl -X POST http://localhost/api/assets \
  -H "Content-Type: application/json" \
  -d '{
    "asset_name": "Customer Database",
    "asset_type": "Database",
    "owner": "Data Team",
    "sensitivity_level": "HIGH"
  }'

# Get all assets
curl http://localhost/api/assets

# Get metrics
curl http://localhost/api/metrics
```

## ☁️ AWS Deployment

### Step 1: Set Up AWS CodeBuild

1. **Create ECR Repository** (optional - buildspec creates it automatically):
```bash
aws ecr create-repository \
  --repository-name data-governance-tool \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1
```

2. **Create CodeBuild Project**:
   - Go to AWS CodeBuild console
   - Create new build project
   - Connect to your source repository (GitHub/CodeCommit)
   - Use `buildspec.yml` from this repo
   - Set environment variables if needed
   - Ensure the service role has ECR permissions

3. **Required IAM Permissions** for CodeBuild:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:CreateRepository"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 2: Set Up EC2 Instance

1. **Launch EC2 Instance**:
   - Amazon Linux 2023 or Ubuntu 22.04
   - Instance type: t3.medium or larger
   - Security group: Allow ports 80, 443, 22
   - Attach IAM role with ECR read permissions

2. **Install Prerequisites on EC2**:
```bash
# For Amazon Linux 2023
sudo yum update -y
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -a -G docker ec2-user

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install AWS CLI (if not already installed)
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

3. **Required IAM Permissions** for EC2:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 3: Deploy Application on EC2

1. **Create application directory**:
```bash
sudo mkdir -p /opt/data-governance-tool
cd /opt/data-governance-tool
```

2. **Copy deployment files to EC2**:
```bash
# From your local machine
scp docker-compose.yml nginx.conf deploy.sh ec2-user@<ec2-ip>:/tmp/

# On EC2
sudo mv /tmp/{docker-compose.yml,nginx.conf,deploy.sh} /opt/data-governance-tool/
sudo chmod +x /opt/data-governance-tool/deploy.sh
```

3. **Set environment variables**:
```bash
# Set these before running deploy.sh
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=123456789012
export ECR_REPOSITORY=data-governance-tool
export IMAGE_TAG=latest
```

4. **Run deployment script**:
```bash
sudo -E /opt/data-governance-tool/deploy.sh
```

The script will:
- Login to ECR
- Pull the latest image
- Create/update environment file
- Deploy using Docker Compose
- Verify the deployment
- Clean up old images

### Step 4: Verify Deployment

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs -f

# Test health endpoint
curl http://localhost/health

# Test from outside
curl http://<ec2-public-ip>/health
```

## 🔄 CI/CD Workflow

1. **Push code** to repository
2. **CodeBuild** automatically triggers:
   - Builds Docker image
   - Pushes to ECR with commit SHA tag and `latest` tag
   - Creates deployment artifacts
3. **Manual deployment** on EC2:
   - Run `deploy.sh` to pull and deploy latest image
   - Can be automated with CodeDeploy or custom automation

## 🔐 Security Best Practices Implemented

- ✅ Multi-stage Docker builds to minimize image size
- ✅ Non-root user in containers
- ✅ Security headers in Nginx
- ✅ Health checks for all services
- ✅ Secret management via environment variables
- ✅ ECR image scanning enabled
- ✅ Resource limits on containers
- ✅ Network isolation with Docker networks

## 📊 API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check for all services |
| `/` | GET | Service information |
| `/api/assets` | GET | Get all data assets (cached) |
| `/api/assets` | POST | Create new data asset |
| `/api/assets/:id` | GET | Get specific asset by ID |
| `/api/metrics` | GET | Get compliance metrics |

## 🧪 Testing

```bash
# Create test data
curl -X POST http://localhost/api/assets \
  -H "Content-Type: application/json" \
  -d '{
    "asset_name": "Sales Database",
    "asset_type": "PostgreSQL",
    "owner": "Sales Team",
    "sensitivity_level": "MEDIUM"
  }'

# Verify caching (should show "source": "cache" on second call)
curl http://localhost/api/assets
curl http://localhost/api/assets

# Check metrics
curl http://localhost/api/metrics
```

## 🔧 Troubleshooting

### Container Issues
```bash
# View all container logs
docker-compose logs

# View specific service logs
docker-compose logs app
docker-compose logs postgres

# Restart services
docker-compose restart

# Rebuild and restart
docker-compose up -d --build
```

### ECR Login Issues
```bash
# Manual ECR login
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

### Database Connection Issues
```bash
# Check database logs
docker-compose logs postgres

# Connect to database manually
docker-compose exec postgres psql -U governance_user -d governance_db
```

## 📈 Monitoring and Logging

```bash
# View real-time logs
docker-compose logs -f

# Check resource usage
docker stats

# View Nginx access logs
docker-compose exec nginx tail -f /var/log/nginx/access.log

# View application logs
docker-compose logs app --tail=100 -f
```

## 🧹 Cleanup

```bash
# Stop and remove containers
docker-compose down

# Remove volumes (WARNING: deletes data)
docker-compose down -v

# Remove images
docker rmi data-governance-tool:latest

# Complete cleanup
docker system prune -a --volumes
```

## 🚀 Production Considerations

1. **Use HTTPS**: Configure SSL certificates in Nginx
2. **Database Backups**: Set up automated PostgreSQL backups
3. **Monitoring**: Integrate CloudWatch or ELK stack
4. **Auto-scaling**: Use ECS/EKS for better scalability
5. **Secrets Management**: Use AWS Secrets Manager instead of .env
6. **CDN**: Add CloudFront for static content
7. **High Availability**: Deploy across multiple AZs
8. **Log Aggregation**: Use CloudWatch Logs or centralized logging

## 📝 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DB_PASSWORD` | PostgreSQL password | `secure_password` |
| `REDIS_PASSWORD` | Redis password | empty |
| `ECR_REGISTRY` | ECR repository URL | - |
| `IMAGE_TAG` | Docker image tag | `latest` |
| `AWS_REGION` | AWS region | `us-east-1` |

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## 📄 License

MIT License - feel free to use this for your projects!

## 🆘 Support

For issues or questions:
- Check the troubleshooting section
- Review container logs
- Open an issue in the repository

---

**Built with ❤️ for DevOps demonstrations**
