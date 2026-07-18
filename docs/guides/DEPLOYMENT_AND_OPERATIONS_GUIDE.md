# CareConnect 2025 Deployment and Operations Guide

## Introduction

### Purpose and Scope

This Deployment and Operations Guide serves as the authoritative resource for deploying, configuring, monitoring, and maintaining the CareConnect healthcare platform in production environments. Unlike development-focused documentation, this guide addresses the unique challenges of running a HIPAA-compliant healthcare application at scale, where reliability, security, and data integrity are not optional—they are regulatory requirements.

**Target Audience**: This guide is designed for:
- **DevOps Engineers** responsible for infrastructure provisioning and CI/CD pipelines
- **Site Reliability Engineers (SREs)** managing production systems and incident response
- **System Administrators** performing day-to-day operational tasks
- **Security Engineers** ensuring compliance with healthcare regulations
- **Technical Leads** making architectural and scaling decisions

**What This Guide Covers**:
- **Infrastructure Architecture**: Understanding the AWS-based multi-tier architecture and why each component was selected
- **Deployment Procedures**: Step-by-step deployment workflows from code commit to production release
- **Monitoring and Observability**: Comprehensive monitoring strategies, alerting, and incident response
- **Security and Compliance**: HIPAA compliance requirements, security best practices, and audit procedures
- **Disaster Recovery**: Backup strategies, recovery procedures, and business continuity planning
- **Troubleshooting**: Systematic approaches to diagnosing and resolving production issues

### Healthcare-Specific Operational Considerations

Operating a healthcare platform differs significantly from standard web applications:

**Regulatory Compliance**: HIPAA and HITECH regulations mandate specific security controls, audit logging, and data handling procedures. Every deployment decision—from encryption methods to backup retention—must consider these requirements.

**Zero Downtime Requirement**: Healthcare providers rely on CareConnect for patient care coordination. Scheduled maintenance windows must be carefully planned, and deployments must use blue-green or canary strategies to avoid service interruptions during critical care hours.

**Data Integrity Above All**: In healthcare, data corruption or loss isn't just inconvenient—it can endanger patient safety. Our backup strategies, database configurations, and deployment procedures prioritize data integrity over speed or convenience.

**Audit Trail Requirements**: Every change to the production system must be logged and traceable. This guide includes procedures for maintaining audit trails that satisfy regulatory scrutiny.

## Infrastructure Overview

### Cloud Architecture Philosophy

CareConnect's infrastructure follows a defense-in-depth approach, where multiple layers of security, redundancy, and monitoring protect patient data and ensure system availability. We've chosen AWS as our cloud provider for its:

- **HIPAA Compliance**: AWS offers Business Associate Agreements (BAA) and maintains HITRUST certification
- **Mature Services**: Proven services like RDS, ECS, and CloudFront reduce operational burden
- **Global Presence**: Multi-region capabilities support disaster recovery and data residency requirements
- **Comprehensive Monitoring**: CloudWatch and related services provide deep observability

The architecture separates concerns across multiple tiers, allowing independent scaling, security hardening, and failure isolation. If the caching layer fails, the application continues serving requests (albeit slower). If a container crashes, ECS automatically replaces it without manual intervention.

### Architecture Diagram and Traffic Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                           Internet                                   │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────────┐
│                    Route 53 (DNS)                                   │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────────┐
│                   CloudFront CDN                                     │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────────┐
│                 Application Load Balancer                           │
└─────────────────────────┬───────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────┐    ┌──────▼──────┐    ┌─────▼──────┐
│   Web App  │    │   Backend   │    │   Admin    │
│   (S3 +    │    │   (ECS +    │    │   Portal   │
│ CloudFront)│    │  Fargate)   │    │   (EC2)    │
└────────────┘    └─────────────┘    └────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
┌───────▼────┐    ┌──────▼──────┐    ┌─────▼──────┐
│    RDS     │    │  ElastiCache│    │   Lambda   │
│ PostgreSQL │    │    Redis    │    │ Functions  │
└────────────┘    └─────────────┘    └────────────┘
        │
┌───────▼────┐
│     S3     │
│  File      │
│ Storage    │
└────────────┘
```

**Understanding the Traffic Flow**:

1. **User Request**: A caregiver opens the CareConnect app on their tablet
2. **DNS Resolution**: Route 53 resolves `careconnect.health` to CloudFront distribution
3. **CDN Layer**: CloudFront serves cached static assets (images, CSS, JavaScript) from edge locations closest to the user, reducing latency
4. **Load Balancing**: Dynamic API requests pass through CloudFront to Application Load Balancer, which distributes traffic across healthy backend containers
5. **Application Processing**: ECS containers running Spring Boot process business logic, enforcing authentication and authorization
6. **Data Access**: Application queries RDS PostgreSQL for persistent data, checks ElastiCache Redis for cached data to avoid expensive database queries
7. **File Operations**: Large files (medical documents, lab results) are stored in and retrieved from S3
8. **Serverless Functions**: Lambda functions handle asynchronous tasks like PDF generation, email sending, and scheduled data exports

This multi-tier architecture ensures that a failure in any single component (except the database) doesn't bring down the entire system.

### Technology Stack and Selection Rationale

Our technology choices balance operational maturity, healthcare compliance requirements, and team expertise:

#### Infrastructure Layer

**Cloud Provider: Amazon Web Services (AWS)**
- **Why AWS over Azure/GCP**: AWS's early entry into healthcare compliance (HIPAA-eligible services since 2013) means more mature tooling and extensive documentation for healthcare workloads. The AWS BAA (Business Associate Agreement) covers a wide range of services, giving us flexibility in architecture choices.
- **Compliance Certifications**: AWS maintains HITRUST, SOC 1/2/3, and ISO 27001 certifications required by many healthcare organizations.

**Infrastructure as Code: Terraform**
- **Why Terraform over CloudFormation**: Terraform's provider-agnostic approach means we could migrate to multi-cloud if needed. Its declarative syntax and state management make infrastructure changes auditable and reversible—critical for regulated environments.
- **State Management**: We use remote state in S3 with DynamoDB locking to prevent concurrent modifications that could corrupt infrastructure state.

**Container Orchestration: ECS with Fargate**
- **Why ECS over Kubernetes**: ECS offers deep AWS integration with less operational overhead. For our team size and application complexity, ECS's managed control plane and native AWS service integration (IAM, CloudWatch, ALB) provides the right balance of power and simplicity.
- **Why Fargate over EC2**: Fargate's serverless model eliminates patching and scaling of underlying VMs. In healthcare, reducing the attack surface and operational burden of OS management is valuable—we focus on application security, not server hardening.

**Load Balancer: Application Load Balancer (ALB)**
- **Layer 7 Routing**: ALB operates at HTTP/HTTPS level, enabling path-based routing (`/api/*` → backend, `/admin/*` → admin portal) and health checks that verify application health, not just network connectivity.
- **WAF Integration**: Tight integration with AWS WAF allows us to protect against OWASP Top 10 vulnerabilities at the perimeter.

**CDN: CloudFront**
- **Global Distribution**: Medical facilities access CareConnect from various geographic locations. CloudFront's 200+ edge locations reduce latency for users worldwide.
- **DDoS Protection**: CloudFront integrates with AWS Shield for DDoS mitigation—important for maintaining availability during attacks.

**DNS: Route 53**
- **Health Checks**: Route 53 monitors endpoint health and automatically fails over to DR region if primary region becomes unhealthy.
- **DNSSEC**: Supports DNSSEC for preventing DNS spoofing attacks.

#### Compute Layer

**Backend: ECS Fargate Containers**
- **Isolation**: Each container runs in its own micro-VM, providing process-level isolation between requests—important when handling sensitive patient data.
- **Auto-scaling**: ECS automatically scales containers based on CPU/memory metrics or custom metrics like request count.
- **Blue-Green Deployments**: ECS native support for blue-green deployments enables zero-downtime updates.

**Frontend: S3 + CloudFront Static Hosting**
- **Infinite Scalability**: S3 automatically scales to handle any request volume. No server capacity planning needed for web assets.
- **Cost Efficiency**: Static hosting is ~10x cheaper than running web servers. For a Flutter web app that's mostly static after build, this is ideal.

**Functions: Lambda for Serverless Tasks**
- **Event-Driven**: Lambda functions respond to S3 events (new file uploaded), SQS messages (async job queue), or scheduled CloudWatch Events (nightly reports).
- **No Idle Costs**: Unlike containers that run 24/7, Lambda charges only for execution time. Perfect for sporadic tasks like PDF generation.

**Admin: EC2 Instances for Administrative Tasks**
- **Why EC2 for Admin**: Admin tasks (database migrations, bulk data imports) sometimes require long-running processes that exceed Lambda's 15-minute timeout.
- **Bastion Host**: EC2 instances also serve as secure bastion hosts for accessing private resources.

#### Storage Layer

**Database: RDS PostgreSQL (Multi-AZ)**
- **Why PostgreSQL**: Advanced features like JSONB columns, row-level security, and excellent ACID compliance make it ideal for healthcare data.
- **Multi-AZ**: Automatic synchronous replication to standby in different Availability Zone provides ~99.95% availability and protects against AZ failures.
- **Automated Backups**: RDS automatically takes daily snapshots and retains transaction logs, enabling point-in-time recovery.

**Cache: ElastiCache Redis**
- **Why Redis over Memcached**: Redis supports complex data structures (sorted sets for leaderboards, pub/sub for real-time features) and persistence, making it suitable for both caching and session storage.
- **Performance**: Caching frequent database queries (user profiles, permissions) reduces database load and improves response times from ~200ms to ~5ms.

**Files: S3 Buckets**
- **Durability**: S3's 99.999999999% durability means medical records are safe from data loss.
- **Lifecycle Policies**: Automatically transition old medical records to Glacier for cost-effective long-term archival while maintaining compliance with retention requirements.
- **Versioning**: S3 versioning protects against accidental deletion and allows recovery of previous file versions.

**Backup: S3 with Lifecycle Policies**
- **Compliance**: Healthcare regulations often require 7-10 year retention of medical records. S3 Glacier Deep Archive provides cost-effective long-term storage.
- **Cross-Region Replication**: Critical backups are replicated to a different AWS region for geographic redundancy.

#### Security Layer

**WAF: AWS WAF for Application Protection**
- **OWASP Protection**: Managed rule sets protect against SQL injection, XSS, and other common attacks without manual rule tuning.
- **Rate Limiting**: Protects API endpoints from brute force and DDoS attacks by limiting request rates per IP.

**Certificates: ACM (AWS Certificate Manager)**
- **Automatic Renewal**: ACM automatically renews SSL/TLS certificates before expiration, preventing the service outages caused by expired certificates.
- **Wildcard Support**: Single wildcard certificate (`*.careconnect.health`) covers all subdomains.

**Secrets: AWS Secrets Manager**
- **Why Secrets Manager over Parameter Store**: Automatic rotation of database passwords and API keys reduces the risk of compromised credentials. In healthcare, regular credential rotation is often a compliance requirement.
- **Encryption**: All secrets are encrypted at rest using AWS KMS with customer-managed keys.

**IAM: Role-Based Access Control**
- **Principle of Least Privilege**: Each ECS task, Lambda function, and admin user has only the permissions needed for their specific function.
- **No Long-Lived Credentials**: ECS tasks use IAM roles (temporary credentials) instead of hardcoded access keys, reducing credential leakage risk.

### Technology Stack Summary

**Infrastructure:**
- **Cloud Provider**: Amazon Web Services (AWS)
- **Infrastructure as Code**: Terraform
- **Container Orchestration**: ECS with Fargate
- **Load Balancer**: Application Load Balancer (ALB)
- **CDN**: CloudFront
- **DNS**: Route 53

**Compute:**
- **Backend**: ECS Fargate containers
- **Frontend**: S3 + CloudFront static hosting
- **Functions**: Lambda for serverless tasks
- **Admin**: EC2 instances for administrative tasks

**Storage:**
- **Database**: RDS PostgreSQL (Multi-AZ)
- **Cache**: ElastiCache Redis
- **Files**: S3 buckets
- **Backup**: S3 with lifecycle policies

**Security:**
- **WAF**: AWS WAF for application protection
- **Certificates**: ACM (AWS Certificate Manager)
- **Secrets**: AWS Secrets Manager
- **IAM**: Role-based access control

## Environment Setup and Strategy

### Environment Structure and Promotion Path

CareConnect employs a four-environment strategy that balances development agility with production safety. Each environment serves a distinct purpose in the software delivery pipeline:

#### 1. Development Environment (`dev`)

**Purpose**: Rapid iteration and feature development without impacting other environments.

**Characteristics**:
- **Local-First**: Developers run most components locally (database, Redis, backend) for fast iteration
- **AWS Integration**: Connects to development S3 buckets and other AWS services for testing cloud integration
- **Relaxed Security**: Uses development credentials and simplified authentication to reduce friction
- **Data**: Synthetic test data only—no real patient information ever exists in dev

**When to Use**: 
- Individual developer feature work
- Unit and integration testing during development
- Debugging and troubleshooting new features

**Infrastructure**: Minimal AWS resources—primarily S3 buckets for file uploads and testing cloud integrations.

#### 2. Staging Environment (`staging`)

**Purpose**: Pre-production validation and integration testing in an environment that mirrors production as closely as possible.

**Characteristics**:
- **Production Mirror**: Infrastructure, networking, and configurations match production (except scale)
- **Integration Testing**: Full end-to-end testing of all components together
- **QA Validation**: Quality assurance team validates features before production release
- **Performance Testing**: Load testing to identify bottlenecks before they impact production users
- **Smaller Scale**: Runs fewer containers and smaller database instances to reduce costs while maintaining architectural parity

**When to Use**:
- Testing feature branches before merging to main
- QA validation of release candidates
- Integration testing of multiple features together
- Training and demo purposes

**Infrastructure**: Full AWS stack but scaled down (1-2 ECS tasks vs 10+ in production, smaller RDS instance).

#### 3. Production Environment (`prod`)

**Purpose**: Serve live traffic for real healthcare providers and patients.

**Characteristics**:
- **High Availability**: Multi-AZ deployment, auto-scaling, automated failover
- **Full Monitoring**: Comprehensive CloudWatch dashboards, alarms, and log aggregation
- **Security Hardening**: All security controls enabled, minimal IAM permissions, encryption everywhere
- **Real Data**: Contains actual patient health information—HIPAA compliance is mandatory
- **Change Control**: Strict deployment procedures with approvals and rollback capabilities

**When to Use**: Only after thorough testing in staging and approval from technical leads.

**Infrastructure**: Full-scale AWS infrastructure with redundancy and auto-scaling.

#### 4. Disaster Recovery Environment (`dr`)

**Purpose**: Geographic redundancy and business continuity in case of regional AWS outage.

**Characteristics**:
- **Passive Standby**: Normally inactive, activated only during DR scenarios
- **Different Region**: Deployed in a separate AWS region (us-west-2 vs us-east-1 for production)
- **Data Replication**: Receives asynchronous replication from production database and S3
- **Lower Cost**: Minimal compute resources until failover is triggered

**When to Use**:
- Primary region experiences significant outage (entire AZ down, networking issues)
- Disaster recovery drills (quarterly validation that DR actually works)

**Infrastructure**: Full infrastructure defined in Terraform but scaled to minimum (1 ECS task, smallest RDS instance) until activated.

### Environment Promotion Workflow

Code flows through environments in a controlled progression:

```
Developer Workstation → dev → staging → production → dr (replicated)
                         ↓       ↓          ↓
                      Feature   QA      Release
                       Test     Test     to Users
```

**Promotion Gates**: Each promotion requires:
- Automated tests passing in current environment
- Manual QA signoff (for staging → production)
- Technical lead approval (for production deployments)
- Deployment during approved change window (production only)

### Environment Configuration Details

#### Development Environment Configuration

```bash
# Local development configuration
export ENVIRONMENT=dev
export DATABASE_URL=jdbc:postgresql://localhost:5432/careconnect_dev
export REDIS_URL=redis://localhost:6379
export JWT_SECRET=dev_jwt_secret_key_32_characters
export AWS_REGION=us-east-1
export S3_BUCKET=careconnect-dev-files
```

#### Staging Environment

```bash
# Staging environment configuration
export ENVIRONMENT=staging
export DATABASE_URL=jdbc:postgresql://staging-db.region.rds.amazonaws.com:5432/careconnect
export REDIS_URL=staging-cache.region.cache.amazonaws.com:6379
export JWT_SECRET=${JWT_SECRET_STAGING}  # From AWS Secrets Manager
export AWS_REGION=us-east-1
export S3_BUCKET=careconnect-staging-files
```

#### Production Environment

```bash
# Production environment configuration
export ENVIRONMENT=prod
export DATABASE_URL=jdbc:postgresql://prod-db.region.rds.amazonaws.com:5432/careconnect
export REDIS_URL=prod-cache.region.cache.amazonaws.com:6379
export JWT_SECRET=${JWT_SECRET_PROD}  # From AWS Secrets Manager
export AWS_REGION=us-east-1
export S3_BUCKET=careconnect-prod-files
```

## AWS Infrastructure Deployment

### Terraform Configuration

#### Main Infrastructure Configuration

This main Terraform configuration file orchestrates all infrastructure components for CareConnect. Rather than defining resources directly, it uses a modular approach where each major component (VPC, database, compute) is encapsulated in its own module. This separation provides several benefits:

**Why Modular Architecture**: 
- **Reusability**: The same VPC module can be used for dev, staging, and prod environments with different parameters
- **Maintainability**: Changes to database configuration don't require touching networking code
- **Testing**: Each module can be tested independently before integration
- **Team Collaboration**: Different team members can work on different modules without conflicts

**State Management**: The `backend "s3"` configuration stores Terraform state remotely in S3, which is critical for team collaboration. Without this, each developer would have their own local state file, leading to infrastructure drift and conflicts. DynamoDB locking prevents two people from running Terraform simultaneously, which could corrupt the state.

**Why These Specific Module Parameters Matter**:
- `multi_az = var.environment == "prod" ? true : false`: Production databases span multiple availability zones for high availability, but dev environments use single-AZ to reduce costs
- `backup_retention_period = var.environment == "prod" ? 30 : 7`: Production keeps 30 days of backups for compliance, dev only needs 7
- `deletion_protection = var.environment == "prod" ? true : false`: Prevents accidental deletion of production database

```hcl
# terraform_aws/main.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "careconnect-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CareConnect"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

# Modules
module "vpc" {
  source = "./modules/vpc"

  environment             = var.environment
  vpc_cidr               = var.vpc_cidr
  availability_zones     = data.aws_availability_zones.available.names
  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
}

module "security_groups" {
  source = "./modules/security_groups"

  environment = var.environment
  vpc_id      = module.vpc.vpc_id
}

module "rds" {
  source = "./modules/rds"

  environment                = var.environment
  vpc_id                    = module.vpc.vpc_id
  subnet_ids                = module.vpc.database_subnet_ids
  security_group_ids        = [module.security_groups.rds_security_group_id]

  db_name                   = var.db_name
  db_username              = var.db_username
  db_password              = var.db_password
  db_instance_class        = var.db_instance_class
  allocated_storage        = var.db_allocated_storage
  max_allocated_storage    = var.db_max_allocated_storage

  backup_retention_period  = var.environment == "prod" ? 30 : 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  multi_az               = var.environment == "prod" ? true : false
  deletion_protection    = var.environment == "prod" ? true : false
}

module "elasticache" {
  source = "./modules/elasticache"

  environment        = var.environment
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_ids = [module.security_groups.cache_security_group_id]

  node_type         = var.cache_node_type
  num_cache_nodes   = var.cache_num_nodes
  parameter_group   = "default.redis7"
  port             = 6379
}

module "ecs" {
  source = "./modules/ecs"

  environment               = var.environment
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  security_group_ids       = [module.security_groups.ecs_security_group_id]

  cluster_name             = "careconnect-${var.environment}"
  task_definition_family   = "careconnect-backend"
  container_image          = var.backend_container_image
  container_port          = 8080

  cpu                     = var.ecs_cpu
  memory                  = var.ecs_memory
  desired_count           = var.ecs_desired_count

  database_url            = module.rds.database_url
  redis_url              = module.elasticache.redis_url

  log_group_name         = "/ecs/careconnect-${var.environment}"
  log_retention_days     = var.environment == "prod" ? 365 : 30
}

module "alb" {
  source = "./modules/alb"

  environment            = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.public_subnet_ids
  security_group_ids    = [module.security_groups.alb_security_group_id]

  certificate_arn       = module.acm.certificate_arn
  target_group_arn      = module.ecs.target_group_arn
}

module "s3" {
  source = "./modules/s3"

  environment           = var.environment
  frontend_bucket_name  = "careconnect-${var.environment}-frontend"
  files_bucket_name     = "careconnect-${var.environment}-files"
  logs_bucket_name      = "careconnect-${var.environment}-logs"

  enable_versioning     = var.environment == "prod" ? true : false
  enable_logging        = true
}

module "cloudfront" {
  source = "./modules/cloudfront"

  environment         = var.environment
  s3_bucket_domain   = module.s3.frontend_bucket_domain
  alb_domain         = module.alb.dns_name
  certificate_arn    = module.acm.certificate_arn

  web_acl_id         = module.waf.web_acl_id
}

module "route53" {
  source = "./modules/route53"

  domain_name          = var.domain_name
  cloudfront_domain   = module.cloudfront.domain_name
  cloudfront_zone_id  = module.cloudfront.hosted_zone_id

  create_health_check = var.environment == "prod" ? true : false
}

module "acm" {
  source = "./modules/acm"

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  route53_zone_id          = module.route53.zone_id
}

module "waf" {
  source = "./modules/waf"

  environment = var.environment

  rate_limit           = var.environment == "prod" ? 10000 : 2000
  enable_geo_blocking  = var.environment == "prod" ? true : false
  blocked_countries    = ["CN", "RU"]  # Example blocked countries
}

module "monitoring" {
  source = "./modules/monitoring"

  environment = var.environment

  cluster_name = module.ecs.cluster_name
  service_name = module.ecs.service_name

  rds_instance_id = module.rds.instance_id
  cache_cluster_id = module.elasticache.cluster_id

  alb_arn = module.alb.arn
  cloudfront_distribution_id = module.cloudfront.distribution_id

  notification_email = var.notification_email
}
```

**Understanding the Module Structure**:

Each `module` block creates a set of related resources. For example, `module "vpc"` creates the entire networking infrastructure (VPC, subnets, NAT gateways, route tables). The module receives inputs via parameters and returns outputs that other modules can use.

**Critical Module Dependencies**:
1. **VPC** must be created first (provides `vpc_id` needed by others)
2. **Security Groups** need the VPC ID to define network rules
3. **RDS** needs both VPC and security groups before it can launch
4. **ECS** needs VPC, security groups, and connects to RDS/ElastiCache
5. **ALB** sits in front of ECS, routing traffic to containers
6. **Monitoring** observes all the above components

This dependency chain is why we use Terraform's module system—it automatically handles creation order based on resource dependencies.

#### VPC Module

The VPC (Virtual Private Cloud) module creates isolated networking infrastructure for CareConnect. Think of it as creating a private data center in AWS—complete with multiple network zones, internet gateways, and routing rules.

**Network Architecture Philosophy**:

CareConnect uses a **three-tier network design** to balance security and accessibility:
1. **Public Subnets**: Host load balancers that accept traffic from the internet
2. **Private Subnets**: Host application containers (ECS tasks) that should NOT be directly accessible from internet
3. **Database Subnets**: Host RDS instances in the most isolated layer, accessible only from application tier

**Why Three Tiers**: This follows the principle of defense-in-depth. Even if an attacker compromises the load balancer, they can't directly access the application layer. Even if they compromise an application container, they can't directly access the database.

**Multi-AZ Design**: Each subnet type is created in multiple Availability Zones (us-east-1a, us-east-1b, etc.). If one AZ fails (rare but happens), the other AZs continue serving traffic. This is why `count = length(var.availability_zones)` appears throughout—we're creating resources in each AZ.

**NAT Gateway Strategy**: Private subnets need internet access for downloading packages and reaching external APIs, but shouldn't accept inbound connections. NAT gateways provide one-way internet access: outbound traffic is allowed, inbound is blocked.

**CIDR Block Math**: The `cidrsubnet(var.vpc_cidr, 8, count.index + 1)` function divides the VPC's IP address space into smaller subnets. For a VPC with CIDR `10.0.0.0/16`, this creates:
- Public subnets: `10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`
- Private subnets: `10.0.11.0/24`, `10.0.12.0/24`, `10.0.13.0/24` (note the +10 offset)
- Database subnets: `10.0.21.0/24`, `10.0.22.0/24`, `10.0.23.0/24` (note the +20 offset)

The offsets ensure no IP overlap between subnet types.

```hcl
# terraform_aws/modules/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = {
    Name = "careconnect-${var.environment}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "careconnect-${var.environment}-igw"
  }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "careconnect-${var.environment}-public-${count.index + 1}"
    Type = "Public"
  }
}

resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "careconnect-${var.environment}-private-${count.index + 1}"
    Type = "Private"
  }
}

resource "aws_subnet" "database" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 20)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "careconnect-${var.environment}-database-${count.index + 1}"
    Type = "Database"
  }
}

# NAT Gateways
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0
  domain = "vpc"

  tags = {
    Name = "careconnect-${var.environment}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "careconnect-${var.environment}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "careconnect-${var.environment}-public-rt"
  }
}

resource "aws_route_table" "private" {
  count = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []
    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.main[count.index].id
    }
  }

  tags = {
    Name = "careconnect-${var.environment}-private-rt-${count.index + 1}"
  }
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count = length(aws_subnet.database)

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
```

**Key VPC Module Concepts Explained**:

**Internet Gateway**: The bridge between our VPC and the public internet. Without this, nothing in the VPC could reach the internet, and the internet couldn't reach our load balancers.

**Route Tables**: Define how traffic flows within the VPC. The public route table says "send `0.0.0.0/0` (all traffic) to the internet gateway." The private route table says "send `0.0.0.0/0` to the NAT gateway" (for outbound-only access).

**Route Table Associations**: Connect subnets to route tables. Public subnets use the public route table (bidirectional internet), private and database subnets use private route tables (outbound-only via NAT).

**Why `depends_on` Matters**: NAT gateways can't be created until the internet gateway exists, because they need a way to route traffic. Terraform's `depends_on` ensures resources are created in the correct order.

**Cost Optimization Note**: NAT gateways are expensive (~$0.045/hour each + $0.045/GB data). We create one per AZ for high availability, but in development environments, you might create just one to save costs (at the expense of AZ resilience).

#### ECS Module

The ECS (Elastic Container Service) module defines how CareConnect's Spring Boot backend runs in production. ECS is AWS's container orchestration service—think of it as the system that ensures your Docker containers are always running, automatically replaces failed containers, and scales up/down based on load.

**Why Fargate Over EC2**: ECS can run containers on EC2 instances (you manage the VMs) or Fargate (AWS manages the infrastructure). We chose Fargate because:
- **No Server Management**: AWS handles patching, scaling, and maintaining the underlying VMs
- **Pay-Per-Container**: You're billed only for container resources used, not idle VM capacity
- **Security**: Each Fargate task runs in its own isolated micro-VM, stronger isolation than shared EC2 instances
- **Healthcare Compliance**: Less infrastructure to audit and secure = easier HIPAA compliance

**Container Insights**: The `containerInsights = "enabled"` setting turns on detailed CloudWatch metrics for every container. This visibility is critical for diagnosing production issues—you can see exactly which container is consuming CPU, making database calls, or experiencing errors.

**Capacity Providers**: The `FARGATE` and `FARGATE_SPOT` configuration allows ECS to use spot instances (cheaper but can be interrupted) for non-critical workloads while using standard Fargate for production traffic. The `base = 1, weight = 100` means "always run at least 1 task on standard Fargate, but prefer standard for all tasks."

**Task Definition Breakdown**:

A "task definition" is like a Docker Compose file—it defines which containers to run, how much CPU/memory they need, environment variables, and health checks. The task definition is versioned, so you can roll back to previous versions if a deployment fails.

**Network Mode `awsvpc`**: Each container gets its own elastic network interface (ENI) with a private IP address. This provides stronger network isolation and allows security groups to control traffic to individual containers (not just the host EC2 instance).

**IAM Roles Explained**:
- **Execution Role** (`ecs_execution_role`): Permissions ECS needs to launch the container (pull from ECR, write to CloudWatch logs, read secrets from Secrets Manager)
- **Task Role** (`ecs_task_role`): Permissions the application code needs at runtime (access S3 buckets, send SNS notifications, etc.)

Separating these roles follows the principle of least privilege—ECS can start containers without giving the application excessive permissions.

**Environment vs. Secrets**: Environment variables are for non-sensitive config (`ENVIRONMENT=prod`). Secrets are pulled from AWS Secrets Manager at runtime and never logged. This prevents accidentally exposing database passwords in CloudWatch Logs.

**Health Check Strategy**: The health check `curl -f http://localhost:${var.container_port}/actuator/health` calls Spring Boot's health endpoint. If this fails 3 times (`retries = 3`), ECS kills the container and starts a new one. The `startPeriod = 60` gives the application 60 seconds to start before health checks begin—important because Spring Boot takes time to initialize.

**Deployment Circuit Breaker**: The `deployment_circuit_breaker` with `rollback = true` is a safety mechanism. If a new deployment causes containers to repeatedly fail health checks, ECS automatically rolls back to the previous version. This prevents a bad deployment from taking down the entire application.

**Auto Scaling Logic**: The `aws_appautoscaling_policy` monitors CPU utilization and automatically scales containers. When average CPU exceeds 70%, ECS launches more containers. When it drops below 70%, ECS terminates excess containers. This balances cost (don't run more containers than needed) with performance (scale up before users notice slowness).

```hcl
# terraform_aws/modules/ecs/main.tf
resource "aws_ecs_cluster" "main" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# Task Definition
resource "aws_ecs_task_definition" "main" {
  family                   = var.task_definition_family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn           = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name  = "careconnect-backend"
      image = var.container_image

      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "SERVER_PORT"
          value = tostring(var.container_port)
        },
        {
          name  = "SPRING_DATASOURCE_URL"
          value = var.database_url
        },
        {
          name  = "SPRING_REDIS_HOST"
          value = var.redis_url
        }
      ]

      secrets = [
        {
          name      = "SPRING_DATASOURCE_PASSWORD"
          valueFrom = var.db_password_secret_arn
        },
        {
          name      = "JWT_SECRET"
          valueFrom = var.jwt_secret_arn
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.container_port}/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])

  tags = {
    Name = var.task_definition_family
  }
}

# ECS Service
resource "aws_ecs_service" "main" {
  name            = "${var.cluster_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count

  launch_type = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "careconnect-backend"
    container_port   = var.container_port
  }

  deployment_configuration {
    maximum_percent         = 200
    minimum_healthy_percent = 100

    deployment_circuit_breaker {
      enable   = true
      rollback = true
    }
  }

  service_registries {
    registry_arn = aws_service_discovery_service.main.arn
  }

  depends_on = [
    aws_lb_listener.main,
    aws_iam_role_policy_attachment.ecs_execution_role_policy
  ]

  tags = {
    Name = "${var.cluster_name}-service"
  }
}

# Auto Scaling
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.cluster_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution" {
  name = "${var.cluster_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-ecs-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

**ECS Module Key Concepts**:

**Service Discovery**: The `service_registries` block registers each container in AWS Cloud Map (service discovery). This allows containers to find each other using DNS names rather than hard-coding IP addresses. When container IP addresses change (due to scaling or failures), service discovery automatically updates the DNS.

**Load Balancer Integration**: The `load_balancer` block connects ECS to the Application Load Balancer. The ALB distributes incoming HTTP requests across all healthy containers. If a container fails its health check, the ALB stops sending traffic to it until it recovers or is replaced.

**Deployment Strategy**: The `maximum_percent = 200, minimum_healthy_percent = 100` configuration enables **blue-green deployments**. When deploying a new version:
1. ECS starts new containers (up to 200% of desired count, e.g., 6 containers if you normally run 3)
2. Once new containers pass health checks, ECS drains traffic from old containers
3. After old containers finish existing requests, ECS terminates them
4. You're left with 100% new containers (the desired count of 3)

This ensures zero downtime during deployments—old containers keep serving requests until new ones are ready.

**Why This Complexity Is Worth It**: While this ECS configuration is extensive, it provides enterprise-grade reliability with automatic recovery, rolling deployments, and autoscaling. In a healthcare application where downtime could impact patient care, these safeguards justify the complexity.

### Deployment Commands

#### Initial Infrastructure Deployment

These commands provision the entire AWS infrastructure from scratch. You'll run this once when setting up a new environment (dev, staging, prod) and rarely thereafter (infrastructure changes are typically done through Terraform updates, not teardown/rebuild).

**Terraform Initialization**: `terraform init` downloads provider plugins (AWS) and sets up the backend (S3 state storage). This must be run whenever you clone the repo or change provider versions.

**Workspaces for Multi-Environment**: Terraform workspaces allow managing multiple environments (dev, staging, prod) with the same configuration but separate state files. `terraform workspace new prod` creates an isolated state for production, preventing accidental changes to dev when you meant to modify prod.

**The Plan-Apply Workflow**: This two-step process is critical for safety:
1. **terraform plan**: Shows what Terraform WOULD do without actually doing it. Review this carefully—if it says "destroy database," something is wrong!
2. **terraform apply**: Actually makes the changes. Only run this after reviewing the plan.

The `-var-file` flag loads environment-specific variables (prod.tfvars) so the same code can deploy different-sized resources for each environment.

**Why Save Outputs**: `terraform output > infrastructure-outputs.txt` captures important values (database endpoint, load balancer DNS) needed by the application. Without this, you'd have to manually look up these values in the AWS console.

```bash
# Navigate to terraform directory
cd terraform_aws

# Initialize Terraform
terraform init

# Create workspace for environment
terraform workspace new prod
terraform workspace select prod

# Plan deployment
terraform plan -var-file="environments/prod.tfvars" -out=tfplan

# Review and apply
terraform apply tfplan

# Save outputs
terraform output > ../infrastructure-outputs.txt
```

#### Environment-Specific Variables

These variable files (`.tfvars`) allow the same Terraform code to create different infrastructure for each environment. Production uses larger, more resilient resources; development uses smaller, cheaper resources.

**Critical Variable Choices Explained**:

**Database Instance Class**: `db.r6g.large` for production is a memory-optimized instance (16 GB RAM) because PostgreSQL performance is heavily memory-dependent. Dev environments might use `db.t4g.micro` (1 GB RAM) to save costs—acceptable for testing but would be too slow for production traffic.

**Storage Auto-Scaling**: `db_max_allocated_storage = 1000` allows PostgreSQL to automatically grow from 100GB to 1TB as data accumulates. This prevents "disk full" failures without pre-allocating expensive storage you don't need yet.

**ECS Auto-Scaling Limits**: `ecs_min_capacity = 2, ecs_max_capacity = 10` means:
- Always run at least 2 containers (for high availability—if one fails, the other handles traffic)
- Never run more than 10 containers (cost control—prevents runaway scaling from attacks or bugs)

Production should always have `min_capacity >= 2` because running a single container means downtime during deployments or failures.

**CPU/Memory Allocation**: `ecs_cpu = 1024, ecs_memory = 2048` allocates 1 vCPU and 2GB RAM per container. Fargate charges based on these values, so right-sizing is important. Too little = out-of-memory errors; too much = wasted money.

**Why Separate Container Images**: `backend_container_image` uses the full ECR URL, not just a tag. This ensures you're pulling from your own private registry, not Docker Hub (where malicious images could exist with similar names).

```hcl
# terraform_aws/environments/prod.tfvars
environment = "prod"
aws_region  = "us-east-1"

# Networking
vpc_cidr = "10.0.0.0/16"

# Database
db_name               = "careconnect"
db_username          = "careconnect_user"
db_instance_class    = "db.r6g.large"
db_allocated_storage = 100
db_max_allocated_storage = 1000

# Cache
cache_node_type = "cache.r6g.large"
cache_num_nodes = 2

# ECS
ecs_cpu           = 1024
ecs_memory        = 2048
ecs_desired_count = 3
ecs_min_capacity  = 2
ecs_max_capacity  = 10

# Domain
domain_name = "careconnect.example.com"

# Notifications
notification_email = "ops@example.com"

# Container Images
backend_container_image = "123456789012.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend:latest"
```

## Application Deployment

### Backend Deployment

Deploying the Spring Boot backend involves building a Docker container image, pushing it to AWS's Elastic Container Registry (ECR), and updating the ECS service to use the new image.

**Why Containers for Backend**: Containers ensure the application runs identically in all environments. If it works on your laptop, it works in production—eliminating "works on my machine" problems. The container includes the exact JDK version, dependencies, and configuration.

#### Docker Build and Push

**The Build Process Explained**:

1. **Maven Build** (`./mvnw clean package`): Compiles Java code, runs tests (skip with `-DskipTests` for faster builds, but NOT recommended for production deployments), and packages everything into a JAR file.

2. **Docker Build**: Uses the Dockerfile in `backend/core/` to create a container image. This typically starts with a base image (e.g., `openjdk:17-jdk-slim`), copies the JAR file, and defines how to run the application.

3. **Tagging**: `docker tag` creates an alias pointing to the same image. We tag as both `latest` (for convenience) and with the ECR repository URL (required for pushing to ECR).

4. **ECR Login**: AWS ECR requires authentication. `get-login-password` retrieves a temporary token valid for 12 hours. Docker uses this to authenticate push operations.

5. **Push to ECR**: Uploads the container image layers to ECR. Only changed layers are uploaded (not the entire image each time), speeding up subsequent pushes.

**Security Note**: Never push `:latest` to production without also tagging with a specific version (e.g., `:v1.2.3` or commit SHA). The `:latest` tag can change, making rollbacks difficult. Always use immutable tags in production.

```bash
# Build backend Docker image
cd backend/core

# Build the application
./mvnw clean package -DskipTests

# Build Docker image
docker build -t careconnect-backend:latest .

# Tag for ECR
docker tag careconnect-backend:latest 123456789012.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend:latest

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com

# Push to ECR
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend:latest
```

#### ECS Service Update

After pushing a new container image to ECR, you must tell ECS to deploy it.

**Force New Deployment**: The `--force-new-deployment` flag tells ECS to pull the latest image and replace existing containers, even if the task definition hasn't changed. This is useful when you push a new image with the same tag (e.g., `:latest`).

**How the Deployment Works**:
1. ECS pulls the new container image from ECR
2. Starts new tasks (containers) running the new image
3. Waits for new tasks to pass health checks (the Spring Boot `/actuator/health` endpoint)
4. Once healthy, updates the load balancer to send traffic to new tasks
5. Drains connections from old tasks (waits for in-flight requests to complete)
6. Terminates old tasks

This entire process takes 2-5 minutes typically. The `aws ecs wait services-stable` command monitors the deployment and only returns when it's complete (or fails).

**Monitoring During Deployment**: Watch CloudWatch Logs for errors from new tasks. If new tasks fail health checks repeatedly, ECS's circuit breaker will automatically roll back to the previous version.

```bash
# Update ECS service with new image
aws ecs update-service \
    --cluster careconnect-prod \
    --service careconnect-prod-service \
    --force-new-deployment

# Monitor deployment
aws ecs wait services-stable \
    --cluster careconnect-prod \
    --services careconnect-prod-service
```

### Frontend Deployment

The Flutter web app is deployed as static files (HTML, JavaScript, CSS) to S3 and distributed globally via CloudFront CDN. Mobile apps follow platform-specific release processes through app stores.

#### Build and Deploy to S3

**Flutter Web Build Process**:

`flutter build web --release` compiles Dart code to optimized JavaScript, minifies assets, and generates a production-ready web app in the `build/web/` directory. The `--release` flag enables:
- Code minification (smaller files = faster load times)
- Dead code elimination (removes unused functions)
- Optimization passes (faster JavaScript execution)

Never deploy a debug build to production—they're 10x larger and include debug symbols attackers could exploit.

**S3 Sync Strategy**: `aws s3 sync` is smarter than `aws s3 cp`. It only uploads files that changed (based on content hash), making deployments faster. The `--delete` flag removes files from S3 that no longer exist locally (e.g., if you renamed a page).

**Why Invalidate CloudFront**: CloudFront caches files at edge locations worldwide (for fast delivery). After deploying new files to S3, CloudFront doesn't automatically know—it might serve old cached versions for hours. The `create-invalidation` command tells CloudFront "discard all cached copies, fetch fresh from S3." The `/*` path means "invalidate everything."

**Cost Note**: CloudFront invalidations cost $0.005 per path invalidated. Invalidating `/*` counts as ~1000 paths. Use specific paths in production to save costs: `--paths "/index.html" "/main.js"`.

```bash
cd frontend

# Install dependencies
flutter pub get

# Build for web
flutter build web --release

# Deploy to S3
aws s3 sync build/web s3://careconnect-prod-frontend --delete

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
    --distribution-id E1234567890123 \
    --paths "/*"
```

#### Mobile App Deployment

**Android App Bundle**: `flutter build appbundle` creates an `.aab` file optimized for Google Play. App bundles allow Google Play to generate APKs customized for each device (different screen sizes, architectures) rather than one giant APK containing everything.

**iOS Archive**: `flutter build ios` generates an Xcode archive (`.ipa` file). This must be signed with your Apple Developer certificate before upload to App Store Connect.

**Why Manual Upload**: Unlike web deployments (fully automated), mobile app stores require human review. You upload through the platform's console, fill out release notes, screenshots, and privacy info, then submit for review. Google typically reviews in hours; Apple in 1-3 days.

**Versioning Strategy**: Always increment version numbers in `pubspec.yaml` before building. App stores reject uploads with duplicate version numbers. Use semantic versioning (e.g., 1.2.3 → 1.2.4 for bug fix, → 1.3.0 for new feature).

```bash
# Android
flutter build appbundle --release

# Upload to Google Play Console
# (Manual process through Google Play Console)

# iOS
flutter build ios --release

# Archive and upload to App Store Connect
# (Use Xcode or Application Loader)
```

### Blue-Green Deployment Strategy

Blue-green deployment is a technique for achieving zero-downtime deployments by running two identical production environments ("blue" and "green") and switching traffic between them. For CareConnect, ECS handles much of this automatically, but understanding the process helps troubleshoot deployment issues.

**What "Blue-Green" Means**: 
- **Blue** = Current production version serving live traffic
- **Green** = New version being deployed
- **Switchover**: Once green is healthy, traffic switches from blue to green
- **Rollback**: If green has issues, immediately switch back to blue

ECS's deployment configuration (`maximum_percent = 200, minimum_healthy_percent = 100`) implements this automatically, but the script below gives you manual control for complex deployments.

#### Automated Blue-Green Deployment

**Script Workflow Explained**:

1. **Fetch Current Task Definition**: Gets the currently running task definition (which includes container image, environment variables, resource limits). This is the "blue" version.

2. **Create New Task Definition**: Uses `jq` to modify the JSON, replacing the old container image with the new one. All other settings (CPU, memory, environment variables) stay the same. This creates the "green" version.

3. **Register New Task Definition**: ECS assigns a new revision number (e.g., `careconnect-backend:42` becomes `:43`).

4. **Update Service**: Tells ECS to use the new task definition. ECS then:
   - Starts new tasks (green)
   - Waits for them to pass health checks
   - Adds them to the load balancer
   - Drains blue tasks
   - Terminates blue tasks

5. **Wait for Stability**: The `aws ecs wait services-stable` command monitors the deployment. It returns when all desired tasks are running and healthy.

6. **Post-Deployment Health Check**: Even after ECS says tasks are healthy, this script performs an additional health check by calling the actual API. This catches issues ECS health checks might miss (e.g., database connection errors that occur after startup).

**Rollback Logic**: If health checks fail after 10 attempts (5 minutes), the script should roll back by updating the service to use the old task definition. In practice, ECS's circuit breaker would have already rolled back by this point, but this provides an additional safety net.

**Why This Manual Script**: While ECS deployments are usually automatic (via CI/CD), having this script allows manual control for:
- Debugging deployment issues
- Testing deployment procedures
- Emergency rollbacks when automation fails

```bash
#!/bin/bash
# scripts/blue-green-deploy.sh

set -e

CLUSTER_NAME="careconnect-prod"
SERVICE_NAME="careconnect-prod-service"
NEW_IMAGE="123456789012.dkr.ecr.us-east-1.amazonaws.com/careconnect-backend:$BUILD_NUMBER"

echo "Starting blue-green deployment..."

# Get current task definition
CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query 'services[0].taskDefinition' \
    --output text)

echo "Current task definition: $CURRENT_TASK_DEF"

# Create new task definition with new image
NEW_TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition $CURRENT_TASK_DEF \
    --query 'taskDefinition' | \
    jq --arg IMAGE "$NEW_IMAGE" '.containerDefinitions[0].image = $IMAGE' | \
    jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)')

NEW_TASK_DEF_ARN=$(echo $NEW_TASK_DEF | aws ecs register-task-definition --cli-input-json file:///dev/stdin --query 'taskDefinition.taskDefinitionArn' --output text)

echo "New task definition: $NEW_TASK_DEF_ARN"

# Update service with new task definition
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $NEW_TASK_DEF_ARN

# Wait for deployment to complete
echo "Waiting for deployment to complete..."
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME

# Health check
echo "Performing health check..."
HEALTH_CHECK_URL="https://api.careconnect.example.com/actuator/health"

for i in {1..10}; do
    if curl -f $HEALTH_CHECK_URL > /dev/null 2>&1; then
        echo "Health check passed"
        break
    else
        echo "Health check failed, attempt $i/10"
        if [ $i -eq 10 ]; then
            echo "Health check failed after 10 attempts, rolling back..."
            # Rollback logic here
            exit 1
        fi
        sleep 30
    fi
done

echo "Blue-green deployment completed successfully!"
```

## Database Management

Managing a PostgreSQL database in production requires careful attention to user permissions, performance tuning, and migration strategies. In healthcare applications, the database is the most critical component—patient data integrity and availability directly impact care quality.

### Database Initialization

Initial database setup involves more than just creating a database. We create multiple users with different permission levels, following the principle of least privilege: each user gets only the permissions needed for their role.

#### Production Database Setup

**User Roles Strategy**:

1. **careconnect_app**: The application user. Has full CRUD permissions on tables but CANNOT create/drop tables or modify schema. This prevents a compromised application from destroying the database structure.

2. **careconnect_readonly**: For analytics and reporting tools. Can only SELECT data, preventing accidental modifications during report generation.

3. **careconnect_backup**: For backup tools. Can SELECT all data but cannot modify anything. Some backup tools need database credentials, and this ensures they can't accidentally corrupt data.

**Why Not Use `postgres` Superuser**: The default `postgres` user has unrestricted access, including the ability to drop the entire database. If an attacker compromises the application and finds database credentials, limiting permissions reduces damage.

**Performance Parameters Explained**:

- `shared_buffers = '1GB'`: Memory PostgreSQL uses for caching. More memory = fewer disk reads = faster queries. Rule of thumb: 25% of system RAM.
- `max_connections = 200`: Maximum concurrent database connections. Each connection consumes memory, so this must balance capacity with resource constraints.
- `log_min_duration_statement = 2000`: Logs any query taking longer than 2 seconds. This helps identify slow queries without logging every query (which would fill disk space quickly).

**Character Encoding**: `UTF8` encoding supports international characters (accents, non-Latin scripts) which is important for patient names and medical terminology from any language.

```sql
-- scripts/init-prod-db.sql

-- Create database
CREATE DATABASE careconnect
    WITH ENCODING 'UTF8'
    LC_COLLATE 'en_US.UTF-8'
    LC_CTYPE 'en_US.UTF-8';

-- Create application user
CREATE USER careconnect_app WITH ENCRYPTED PASSWORD 'secure_password_here';
GRANT CONNECT ON DATABASE careconnect TO careconnect_app;
GRANT USAGE ON SCHEMA public TO careconnect_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO careconnect_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO careconnect_app;

-- Create read-only user for reporting
CREATE USER careconnect_readonly WITH ENCRYPTED PASSWORD 'readonly_password_here';
GRANT CONNECT ON DATABASE careconnect TO careconnect_readonly;
GRANT USAGE ON SCHEMA public TO careconnect_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO careconnect_readonly;

-- Create backup user
CREATE USER careconnect_backup WITH ENCRYPTED PASSWORD 'backup_password_here';
GRANT CONNECT ON DATABASE careconnect TO careconnect_backup;
GRANT USAGE ON SCHEMA public TO careconnect_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO careconnect_backup;

-- Connect to the database
\c careconnect;

-- Configure performance parameters
ALTER SYSTEM SET shared_buffers = '1GB';
ALTER SYSTEM SET max_connections = 200;
ALTER SYSTEM SET log_min_duration_statement = 2000; -- Log queries taking > 2s
SELECT pg_reload_conf();
```

### Database Migration Strategy

CareConnect **does not use Flyway in production or ECS deploys**. Schema evolves through:

1. **`SchemaPatchRunner`** — idempotent JDBC patches run at every application startup (`backend/core/src/main/java/com/careconnect/config/SchemaPatchRunner.java`). Add new production DDL here.
2. **Hibernate `ddl-auto=update`** — ECS sets `SPRING_JPA_HIBERNATE_DDL_AUTO=update` via CloudFormation; JPA creates/alters tables from `@Entity` classes.
3. **`db/migration/*.sql`** — canonical SQL reference for developers; optional local use via `psql` or `./mvnw flyway:migrate` only (not wired into GitHub Actions or ECS).

**Why not Flyway in prod**: Flyway is disabled to avoid circular dependency with JPA startup. Deploy pipelines (`backend-app-deploy.yml`, `backend-full-deploy.yml`) do not run migration jobs.

#### Optional local Flyway (development only)

Flyway Maven plugin and SQL files remain available for local verification. This is **not** part of the production deploy path.

**How Flyway Works** (local optional use only):
1. **Version-Named Files**: Migrations are SQL files named `V001__description.sql`, `V002__another_change.sql`. The version number determines execution order.
2. **Checksum Validation**: Flyway calculates a checksum of each migration file. If you modify a file after it's been applied, Flyway detects the change and fails—preventing accidental modifications to historical migrations.
3. **Automatic Execution**: On application startup (or via Maven command), Flyway checks which migrations haven't run yet and executes them in order.

**Configuration Parameters**:
- `baselineOnMigrate=true`: If the database already has tables (e.g., you're adding Flyway to an existing database), this treats the current schema as "version 0" instead of failing.
- `validateOnMigrate=true`: Before running migrations, verifies all previously applied migrations haven't been modified. Prevents database corruption from changing historical migrations.

**Common Pitfall**: Never modify a migration file after it's been deployed. If you need to change something, create a NEW migration file that reverses or corrects the previous one.

```xml
<!-- backend/core/pom.xml - Flyway plugin -->
<plugin>
    <groupId>org.flywaydb</groupId>
    <artifactId>flyway-maven-plugin</artifactId>
    <version>9.16.0</version>
    <configuration>
        <url>jdbc:postgresql://${db.host}:${db.port}/${db.name}</url>
        <user>${db.username}</user>
        <password>${db.password}</password>
        <locations>
            <location>filesystem:src/main/resources/db/migration</location>
        </locations>
        <baselineOnMigrate>true</baselineOnMigrate>
        <validateOnMigrate>true</validateOnMigrate>
    </configuration>
</plugin>
```

#### Sample Migration Files

These migration files demonstrate best practices for database schema evolution. Each file is versioned (V001, V002, V003) and runs exactly once in order.

**Key Design Patterns in These Migrations**:

**Primary Keys as BIGSERIAL**: Using `BIGSERIAL` instead of `SERIAL` provides 64-bit integers (vs 32-bit), supporting up to 9 quintillion records. While healthcare apps rarely need this, the performance cost is negligible and it prevents "ran out of IDs" failures 10 years from now.

**Foreign Key Constraints**: `REFERENCES users(id) ON DELETE CASCADE` ensures referential integrity. If a user is deleted, their vital signs and medications are automatically deleted too, preventing orphaned records. Healthcare compliance often requires retaining records even after account deletion, so in production you might use `ON DELETE RESTRICT` instead.

**Check Constraints**: `CHECK (role IN ('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER'))` enforces valid values at the database level. Even if application code has a bug, invalid roles can't be inserted. This is defense-in-depth.

**Index Strategy**:
- `idx_users_email`: Unique index on email enables fast lookup during login
- `idx_vital_signs_user_type_time`: Composite index optimized for querying "all blood pressure readings for user X in the last month"—a common healthcare query pattern
- `measurement_time DESC`: Descending order because we usually want recent measurements first

**Auto-updating Timestamps**: The trigger `update_updated_at_column()` automatically sets `updated_at` on every UPDATE. This audit trail is critical in healthcare for compliance and debugging ("when did this medication dosage change?").

**DECIMAL for Medical Values**: Vital signs use `DECIMAL(10,2)` not `FLOAT` because floating-point arithmetic has rounding errors. For blood pressure like "120.5 mmHg," exact precision matters for medical accuracy.

```sql
-- src/main/resources/db/migration/V001__Create_initial_schema.sql
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) CHECK (role IN ('PATIENT', 'CAREGIVER', 'FAMILY_MEMBER')) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_active ON users(active);

-- Create trigger for updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at = CURRENT_TIMESTAMP;
   RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- src/main/resources/db/migration/V002__Create_vital_signs_table.sql
CREATE TABLE vital_signs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL,
    value DECIMAL(10,2) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    notes TEXT,
    measurement_time TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_vital_signs_user_id ON vital_signs(user_id);
CREATE INDEX idx_vital_signs_type ON vital_signs(type);
CREATE INDEX idx_vital_signs_measurement_time ON vital_signs(measurement_time);
CREATE INDEX idx_vital_signs_user_type_time ON vital_signs(user_id, type, measurement_time DESC);

CREATE TRIGGER update_vital_signs_updated_at BEFORE UPDATE ON vital_signs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- src/main/resources/db/migration/V003__Add_health_monitoring_tables.sql
CREATE TABLE medications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    dosage VARCHAR(100),
    frequency VARCHAR(100),
    start_date DATE,
    end_date DATE,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_medications_user_id ON medications(user_id);
CREATE INDEX idx_medications_active ON medications(active);

CREATE TRIGGER update_medications_updated_at BEFORE UPDATE ON medications
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TABLE allergies (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    allergen VARCHAR(255) NOT NULL,
    severity VARCHAR(20) CHECK (severity IN ('MILD', 'MODERATE', 'SEVERE')) NOT NULL,
    reaction TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_allergies_user_id ON allergies(user_id);

CREATE TRIGGER update_allergies_updated_at BEFORE UPDATE ON allergies
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
```

### Database Backup Strategy

Database backups are critical for disaster recovery and compliance. Healthcare regulations often require maintaining backups for 7-10 years. Our strategy combines automated daily backups with AWS RDS's built-in continuous backup.

**Two-Tier Backup Approach**:
1. **RDS Automated Backups**: Continuous transaction log backups enabling point-in-time recovery within the last 30 days
2. **Manual pg_dump Backups**: Full logical backups stored in S3 with long-term retention for compliance

#### Automated Backup Script

**Why Both RDS Snapshots AND pg_dump**:
- **RDS Snapshots**: Fast to restore, perfect for recent disasters (accidental deletion, bad deployment)
- **pg_dump Backups**: Platform-independent SQL dumps you can restore to any PostgreSQL instance (not locked into AWS)

**Script Components Explained**:

**Custom Format**: `--format=custom` creates a PostgreSQL-specific binary format that's:
- Smaller than plain SQL (important for large databases)
- Faster to restore than plain SQL
- Allows selective restoration (restore just one table if needed)

**Compression Level 9**: `--compress=9` provides maximum compression at the cost of CPU time. For nightly backups, we have time; for emergency backups, you might use lower compression for speed.

**Clean and Create**: `--clean --create` means the restore script will:
- Drop the database if it exists (`--clean`)
- Recreate the database (`--create`)
This makes restores idempotent—running twice gives same result.

**Retention Policy**: The script deletes backups older than `RETENTION_DAYS` (30). Adjust this based on compliance requirements. Healthcare apps might need 2555 days (7 years).

**Backup Verification**: The script checks if the backup file is at least 1MB. A tiny backup likely indicates a failure (empty database or pg_dump error). In production, you'd also test-restore backups periodically to verify they're actually usable.

```bash
#!/bin/bash
# scripts/backup-database.sh

set -e

# Configuration
DB_HOST="prod-db.region.rds.amazonaws.com"
DB_NAME="careconnect"
DB_USER="careconnect_backup"
DB_PASSWORD="$DB_BACKUP_PASSWORD"
S3_BUCKET="careconnect-prod-backups"
BACKUP_PREFIX="database"
RETENTION_DAYS=30

# Create timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="${BACKUP_PREFIX}_${TIMESTAMP}.sql.gz"

echo "Starting database backup: $BACKUP_FILENAME"

# Create backup
pg_dump \
    --host=$DB_HOST \
    --username=$DB_USER \
    --no-password \
    --format=custom \
    --compress=9 \
    --clean \
    --create \
    --dbname=$DB_NAME \
    --file=/tmp/$BACKUP_FILENAME
export PGPASSWORD=$DB_PASSWORD

# Upload to S3
aws s3 cp /tmp/$BACKUP_FILENAME s3://$S3_BUCKET/database/

# Clean up local file
rm /tmp/$BACKUP_FILENAME

# Clean up old backups
aws s3 ls s3://$S3_BUCKET/database/ | \
    awk '{print $4}' | \
    head -n -$RETENTION_DAYS | \
    while read file; do
        aws s3 rm s3://$S3_BUCKET/database/$file
    done

echo "Database backup completed: $BACKUP_FILENAME"

# Verify backup
BACKUP_SIZE=$(aws s3 ls s3://$S3_BUCKET/database/$BACKUP_FILENAME --summarize | grep "Total Size" | awk '{print $3}')

if [ "$BACKUP_SIZE" -gt 1000000 ]; then  # 1MB minimum
    echo "Backup verification passed: $BACKUP_SIZE bytes"
else
    echo "Backup verification failed: $BACKUP_SIZE bytes"
    exit 1
fi
```

#### Point-in-Time Recovery

RDS's automated backups enable point-in-time recovery (PITR)—restoring the database to any second within the last 30 days. This is invaluable when you discover data corruption hours after it occurred.

**When to Use PITR**:
- Accidental data deletion discovered hours later ("someone deleted all patients yesterday at 2:15 PM")
- Bad migration or deployment corrupted data
- Ransomware attack encrypted your data (restore to just before attack)

**How PITR Works**:
1. **Base Snapshot**: RDS takes daily snapshots of your entire database
2. **Transaction Logs**: Every database modification is logged continuously
3. **Restoration**: To restore to time T, RDS takes the most recent snapshot before T, then replays transaction logs up to time T

**Script Workflow**:
1. Specify restore time (e.g., "2024-10-15 14:30:00" - just before the bad deployment)
2. AWS creates a NEW RDS instance with data from that exact time
3. You can query this instance to verify it has correct data
4. If good, redirect application to this instance; if not, delete and try different time

**Why Restore to New Instance**: Never restore to the production instance directly—you might overwrite good data with bad data if you picked wrong restore time. Always restore to a new instance, verify, THEN promote to production.

**Cost Note**: The restored instance runs at full cost until you delete it. Don't forget to clean up after recovery!

```bash
#!/bin/bash
# scripts/restore-database.sh

set -e

# Parameters
RESTORE_TIME="$1"  # Format: YYYY-MM-DD HH:MM:SS
SOURCE_DB_INSTANCE="careconnect-prod-db"
TARGET_DB_INSTANCE="careconnect-restore-$(date +%Y%m%d%H%M%S)"

if [ -z "$RESTORE_TIME" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS'"
    exit 1
fi

echo "Starting point-in-time recovery to: $RESTORE_TIME"

# Create restored DB instance
aws rds restore-db-instance-to-point-in-time \
    --target-db-instance-identifier $TARGET_DB_INSTANCE \
    --source-db-instance-identifier $SOURCE_DB_INSTANCE \
    --restore-time "$RESTORE_TIME" \
    --db-instance-class db.r6g.large \
    --no-multi-az \
    --no-publicly-accessible

echo "Restore initiated. Instance: $TARGET_DB_INSTANCE"

# Wait for instance to be available
aws rds wait db-instance-available \
    --db-instance-identifier $TARGET_DB_INSTANCE

echo "Database restore completed: $TARGET_DB_INSTANCE"

# Get endpoint
RESTORE_ENDPOINT=$(aws rds describe-db-instances \
    --db-instance-identifier $TARGET_DB_INSTANCE \
    --query 'DBInstances[0].Endpoint.Address' \
    --output text)

echo "Restored database endpoint: $RESTORE_ENDPOINT"
```

## CI/CD Pipeline

Continuous Integration and Continuous Deployment (CI/CD) automate the path from code commit to production deployment. For CareConnect, GitHub Actions orchestrates testing, building, and deploying both backend and frontend whenever code is pushed to the main branch.

**Why Automate Deployment**: Manual deployments are error-prone—it's easy to forget a step, deploy to the wrong environment, or skip testing. Automated pipelines ensure every deployment follows the same tested process.

**Pipeline Philosophy**: Our pipeline follows a strict sequence: Test → Build → Deploy → Migrate → Smoke Test → Notify. If any step fails, the pipeline stops immediately, preventing broken code from reaching production.

### GitHub Actions Workflow

GitHub Actions is tightly integrated with GitHub, making it ideal for open-source and team projects. Workflows are defined in YAML and run in ephemeral containers, ensuring clean build environments every time.

**Workflow Triggers Explained**:
- `on: push: branches: [main]`: Automatically deploys whenever code is merged to main branch
- `workflow_dispatch`: Allows manual triggering from GitHub UI (useful for hotfixes)

**Job Dependencies**: The `needs` keyword creates a directed acyclic graph (DAG) of jobs:
```
test → build-and-deploy-backend → run-migrations → smoke-tests → notify
    → build-and-deploy-frontend ───────────↗
```
Backend and frontend deploy in parallel (faster), but migrations wait for backend deployment (migrations need the new code to be live).

**Services in GitHub Actions**: The `services: postgres:` block starts a PostgreSQL container alongside the test runner. This gives tests a real database rather than mocks, catching more bugs. The health check ensures PostgreSQL is ready before tests run.

**Why Cache Maven Packages**: Maven downloads dependencies from the internet, which is slow. The `cache` action stores `~/.m2` between builds, turning 5-minute dependency downloads into 10-second cache restores.

**Immutable Image Tags**: Each build tags the Docker image with `$GITHUB_SHA` (the git commit hash). This creates an immutable reference—you can always deploy commit `abc123` exactly as it was built, essential for rollbacks.

**Secrets Management**: `${{ secrets.AWS_ACCESS_KEY_ID }}` references secrets stored in GitHub's encrypted secrets store. Never hardcode credentials in workflows—they'd be visible in version history forever.

**Deployment Safety**: The workflow waits (`aws ecs wait services-stable`) until deployment completes before running smoke tests. This prevents false positives from testing the old version while new version is still deploying.

**Smoke Tests Strategy**: After deployment, the pipeline makes real HTTP requests to production endpoints:
- `curl -f` fails if HTTP status isn't 2xx, causing the job to fail
- Testing `/actuator/health` verifies Spring Boot started correctly
- Testing a known-failure case (invalid login) verifies the API logic works, not just the health endpoint

**Notification Strategy**: The `if: always()` ensures notifications run even if previous jobs failed. The `if: ${{ success() }}` vs `if: ${{ failure() }}` conditionals send appropriate messages. This is how the team learns about deployment results immediately via Slack.

```yaml
# .github/workflows/deploy-production.yml
name: Deploy to Production

on:
  push:
    branches: [main]
  workflow_dispatch:

env:
  AWS_REGION: us-east-1
  ECR_REPOSITORY: careconnect-backend
  ECS_CLUSTER: careconnect-prod
  ECS_SERVICE: careconnect-prod-service

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: careconnect_test
        ports:
          - 5432:5432
        options: --health-cmd="pg_isready" --health-interval=10s --health-timeout=5s --health-retries=3

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up JDK 17
      uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'adopt'

    - name: Cache Maven packages
      uses: actions/cache@v3
      with:
        path: ~/.m2
        key: ${{ runner.os }}-m2-${{ hashFiles('**/pom.xml') }}
        restore-keys: ${{ runner.os }}-m2

    - name: Run backend tests
      working-directory: backend/core
      run: ./mvnw test
      env:
        SPRING_DATASOURCE_URL: jdbc:postgresql://localhost:5432/careconnect_test
        SPRING_DATASOURCE_USERNAME: postgres
        SPRING_DATASOURCE_PASSWORD: test

    - name: Set up Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.9.2'

    - name: Run frontend tests
      working-directory: frontend
      run: |
        flutter pub get
        flutter test

  build-and-deploy-backend:
    needs: test
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Login to Amazon ECR
      id: login-ecr
      uses: aws-actions/amazon-ecr-login@v1

    - name: Build and tag Docker image
      working-directory: backend/core
      run: |
        ./mvnw clean package -DskipTests
        docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA .
        docker tag $ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA $ECR_REGISTRY/$ECR_REPOSITORY:latest
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}

    - name: Push image to Amazon ECR
      run: |
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA
        docker push $ECR_REGISTRY/$ECR_REPOSITORY:latest
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}

    - name: Deploy to Amazon ECS
      run: |
        # Get current task definition
        TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition careconnect-backend --query 'taskDefinition')

        # Create new task definition with new image
        NEW_TASK_DEFINITION=$(echo $TASK_DEFINITION | jq --arg IMAGE "$ECR_REGISTRY/$ECR_REPOSITORY:$GITHUB_SHA" '.containerDefinitions[0].image = $IMAGE' | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .placementConstraints, .compatibilities, .registeredAt, .registeredBy)')

        # Register new task definition
        NEW_TASK_DEF_ARN=$(echo $NEW_TASK_DEFINITION | aws ecs register-task-definition --cli-input-json file:///dev/stdin --query 'taskDefinition.taskDefinitionArn' --output text)

        # Update service
        aws ecs update-service --cluster $ECS_CLUSTER --service $ECS_SERVICE --task-definition $NEW_TASK_DEF_ARN

        # Wait for deployment
        aws ecs wait services-stable --cluster $ECS_CLUSTER --services $ECS_SERVICE
      env:
        ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}

  build-and-deploy-frontend:
    needs: test
    runs-on: ubuntu-latest

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.9.2'

    - name: Build web app
      working-directory: frontend
      run: |
        flutter pub get
        flutter build web --release

    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v3
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Deploy to S3
      working-directory: frontend
      run: |
        aws s3 sync build/web s3://careconnect-prod-frontend --delete

    - name: Invalidate CloudFront
      run: |
        DISTRIBUTION_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Aliases.Items, 'careconnect.example.com')].Id" --output text)
        aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"

  # Schema is applied at ECS task startup (SchemaPatchRunner + Hibernate ddl-auto).
  # Do not add a Flyway migrate step for production deploys.

  smoke-tests:
    needs: [build-and-deploy-backend, build-and-deploy-frontend]
    runs-on: ubuntu-latest

    steps:
    - name: Health check API
      run: |
        curl -f https://api.careconnect.example.com/actuator/health
        curl -f https://api.careconnect.example.com/actuator/info

    - name: Health check frontend
      run: |
        curl -f https://careconnect.example.com

    - name: Run API tests
      run: |
        # Run basic API tests
        curl -X POST https://api.careconnect.example.com/api/auth/login \
          -H "Content-Type: application/json" \
          -d '{"email":"test@example.com","password":"invalid"}' \
          | grep -q "Invalid credentials"

  notify:
    needs: [build-and-deploy-backend, build-and-deploy-frontend, smoke-tests]
    runs-on: ubuntu-latest
    if: always()

    steps:
    - name: Notify success
      if: ${{ success() }}
      run: |
        curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
          -H 'Content-type: application/json' \
          --data '{"text":"✅ Production deployment successful!"}'

    - name: Notify failure
      if: ${{ failure() }}
      run: |
        curl -X POST ${{ secrets.SLACK_WEBHOOK_URL }} \
          -H 'Content-type: application/json' \
          --data '{"text":"❌ Production deployment failed!"}'
```

### Rollback Strategy

```bash
#!/bin/bash
# scripts/rollback.sh

set -e

CLUSTER_NAME="careconnect-prod"
SERVICE_NAME="careconnect-prod-service"

echo "Starting rollback process..."

# Get current and previous task definitions
CURRENT_TASK_DEF=$(aws ecs describe-services \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME \
    --query 'services[0].taskDefinition' \
    --output text)

echo "Current task definition: $CURRENT_TASK_DEF"

# Extract revision number
CURRENT_REVISION=$(echo $CURRENT_TASK_DEF | grep -o '[0-9]*$')
PREVIOUS_REVISION=$((CURRENT_REVISION - 1))

if [ $PREVIOUS_REVISION -lt 1 ]; then
    echo "Cannot rollback: no previous revision available"
    exit 1
fi

PREVIOUS_TASK_DEF=$(echo $CURRENT_TASK_DEF | sed "s/:$CURRENT_REVISION/:$PREVIOUS_REVISION/")

echo "Rolling back to: $PREVIOUS_TASK_DEF"

# Update service with previous task definition
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --task-definition $PREVIOUS_TASK_DEF

# Wait for rollback to complete
echo "Waiting for rollback to complete..."
aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME

# Health check
echo "Performing health check..."
sleep 30  # Wait for service to fully start

HEALTH_CHECK_URL="https://api.careconnect.example.com/actuator/health"

for i in {1..5}; do
    if curl -f $HEALTH_CHECK_URL > /dev/null 2>&1; then
        echo "Rollback successful - health check passed"
        exit 0
    else
        echo "Health check failed, attempt $i/5"
        sleep 30
    fi
done

echo "Rollback failed - health check did not pass"
exit 1
```

## Monitoring and Logging

### CloudWatch Dashboard

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ECS", "CPUUtilization", "ServiceName", "careconnect-prod-service", "ClusterName", "careconnect-prod"],
          [".", "MemoryUtilization", ".", ".", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "ECS Service Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "careconnect-prod-db"],
          [".", "DatabaseConnections", ".", "."],
          [".", "ReadLatency", ".", "."],
          [".", "WriteLatency", ".", "."]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "RDS Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", "careconnect-prod-alb"],
          [".", "TargetResponseTime", ".", "."],
          [".", "HTTPCode_Target_2XX_Count", ".", "."],
          [".", "HTTPCode_Target_4XX_Count", ".", "."],
          [".", "HTTPCode_Target_5XX_Count", ".", "."]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "us-east-1",
        "title": "Load Balancer Metrics"
      }
    }
  ]
}
```

### Application Metrics

```java
// config/MetricsConfig.java
@Configuration
public class MetricsConfig {

    @Bean
    public MeterRegistry meterRegistry() {
        return new CloudWatchMeterRegistry(
            CloudWatchConfig.DEFAULT,
            Clock.SYSTEM,
            CloudWatchAsyncClient.create()
        );
    }

    @Bean
    @ConditionalOnMissingBean
    public TimedAspect timedAspect(MeterRegistry registry) {
        return new TimedAspect(registry);
    }
}

// Custom metrics in service classes
@Service
public class HealthService {

    private final Counter vitalSignsRecorded;
    private final Timer apiResponseTime;
    private final Gauge activeUsers;

    public HealthService(MeterRegistry meterRegistry) {
        this.vitalSignsRecorded = Counter.builder("careconnect.vitalsigns.recorded")
            .description("Number of vital signs recorded")
            .register(meterRegistry);

        this.apiResponseTime = Timer.builder("careconnect.api.response.time")
            .description("API response time")
            .register(meterRegistry);

        this.activeUsers = Gauge.builder("careconnect.users.active")
            .description("Number of active users")
            .register(meterRegistry, this, HealthService::getActiveUserCount);
    }

    @Timed(value = "careconnect.vitalsigns.record", description = "Time to record vital sign")
    public VitalSign recordVitalSign(VitalSignRequest request) {
        // Implementation
        vitalSignsRecorded.increment();
        return vitalSign;
    }

    private int getActiveUserCount() {
        // Implementation to count active users
        return 0;
    }
}
```

### Alerting Configuration

```yaml
# cloudwatch-alarms.yml (for Terraform or CloudFormation)
HighCPUUtilization:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmDescription: High CPU utilization on ECS service
    MetricName: CPUUtilization
    Namespace: AWS/ECS
    Statistic: Average
    Period: 300
    EvaluationPeriods: 2
    Threshold: 80
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: ServiceName
        Value: careconnect-prod-service
      - Name: ClusterName
        Value: careconnect-prod
    AlarmActions:
      - !Ref SNSTopic

HighMemoryUtilization:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmDescription: High memory utilization on ECS service
    MetricName: MemoryUtilization
    Namespace: AWS/ECS
    Statistic: Average
    Period: 300
    EvaluationPeriods: 2
    Threshold: 85
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: ServiceName
        Value: careconnect-prod-service
      - Name: ClusterName
        Value: careconnect-prod
    AlarmActions:
      - !Ref SNSTopic

DatabaseConnectionsHigh:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmDescription: High database connections
    MetricName: DatabaseConnections
    Namespace: AWS/RDS
    Statistic: Average
    Period: 300
    EvaluationPeriods: 2
    Threshold: 80
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: DBInstanceIdentifier
        Value: careconnect-prod-db
    AlarmActions:
      - !Ref SNSTopic

APIErrorRate:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmDescription: High API error rate
    MetricName: HTTPCode_Target_5XX_Count
    Namespace: AWS/ApplicationELB
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 2
    Threshold: 10
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: LoadBalancer
        Value: careconnect-prod-alb
    AlarmActions:
      - !Ref SNSTopic
```

### Log Aggregation

```yaml
# cloudwatch-logs.yml
version: '3'

x-logging: &default-logging
  driver: "awslogs"
  options:
    awslogs-group: "/ecs/careconnect-prod"
    awslogs-region: "us-east-1"
    awslogs-stream-prefix: "ecs"

services:
  backend:
    logging: *default-logging
    environment:
      - LOGGING_LEVEL_ROOT=INFO
      - LOGGING_LEVEL_COM_CARECONNECT=DEBUG
      - LOGGING_PATTERN_CONSOLE=%d{HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n
      - LOGGING_PATTERN_FILE=%d{yyyy-MM-dd HH:mm:ss.SSS} [%thread] %-5level %logger{36} - %msg%n
```

## Security and Compliance

### Security Hardening

#### Network Security

```hcl
# Security Groups
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  name_prefix = "${var.environment}-ecs-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.environment}-ecs-sg"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-rds-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  tags = {
    Name = "${var.environment}-rds-sg"
  }
}
```

#### WAF Configuration

```hcl
# Web Application Firewall
resource "aws_wafv2_web_acl" "main" {
  name  = "careconnect-${var.environment}-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 10000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }

  # SQL injection protection
  rule {
    name     = "SQLInjectionRule"
    priority = 2

    action {
      block {}
    }

    statement {
      sqli_match_statement {
        field_to_match {
          body {}
        }

        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }

        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "SQLInjectionRule"
      sampled_requests_enabled   = true
    }
  }

  # XSS protection
  rule {
    name     = "XSSRule"
    priority = 3

    action {
      block {}
    }

    statement {
      xss_match_statement {
        field_to_match {
          body {}
        }

        text_transformation {
          priority = 0
          type     = "URL_DECODE"
        }

        text_transformation {
          priority = 1
          type     = "HTML_ENTITY_DECODE"
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "XSSRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "careconnect-${var.environment}-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "careconnect-${var.environment}-waf"
  }
}
```

### Secrets Management

#### AWS Secrets Manager Configuration

```hcl
# Database password
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "careconnect/${var.environment}/db-password"
  description             = "Database password for CareConnect ${var.environment}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name        = "careconnect-${var.environment}-db-password"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# JWT secret
resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "careconnect/${var.environment}/jwt-secret"
  description             = "JWT secret for CareConnect ${var.environment}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name        = "careconnect-${var.environment}-jwt-secret"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret
}

# API keys
resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "careconnect/${var.environment}/api-keys"
  description             = "API keys for CareConnect ${var.environment}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Name        = "careconnect-${var.environment}-api-keys"
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "api_keys" {
  secret_id = aws_secretsmanager_secret.api_keys.id
  secret_string = jsonencode({
    deepseek_api_key = var.deepseek_api_key
    openai_api_key   = var.openai_api_key
    stripe_secret_key = var.stripe_secret_key
  })
}
```

### HIPAA Compliance

#### Encryption Configuration

```yaml
# RDS Encryption
DBInstance:
  Type: AWS::RDS::DBInstance
  Properties:
    StorageEncrypted: true
    KmsKeyId: !Ref DatabaseKMSKey

# S3 Bucket Encryption
S3Bucket:
  Type: AWS::S3::Bucket
  Properties:
    BucketEncryption:
      ServerSideEncryptionConfiguration:
        - ServerSideEncryptionByDefault:
            SSEAlgorithm: aws:kms
            KMSMasterKeyID: !Ref S3KMSKey

# ECS Task Definition - Encryption in transit
TaskDefinition:
  Type: AWS::ECS::TaskDefinition
  Properties:
    ContainerDefinitions:
      - Name: careconnect-backend
        Environment:
          - Name: SERVER_SSL_ENABLED
            Value: "true"
          - Name: SERVER_SSL_KEY_STORE_TYPE
            Value: "PKCS12"
```

#### Audit Logging

```java
// Audit configuration
@Configuration
@EnableJpaAuditing
public class AuditConfig {

    @Bean
    public AuditorAware<String> auditorProvider() {
        return new SpringSecurityAuditorAware();
    }
}

// Audit entity
@Entity
@Table(name = "audit_logs")
public class AuditLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String userId;

    @Column(nullable = false)
    private String action;

    @Column(nullable = false)
    private String resource;

    @Column(columnDefinition = "TEXT")
    private String details;

    @Column(nullable = false)
    private String ipAddress;

    @Column(nullable = false)
    private String userAgent;

    @CreationTimestamp
    private LocalDateTime timestamp;

    // Constructors, getters, setters
}

// Audit service
@Service
public class AuditService {

    private final AuditLogRepository auditLogRepository;

    @Async
    public void logAction(String userId, String action, String resource, String details) {
        AuditLog auditLog = new AuditLog();
        auditLog.setUserId(userId);
        auditLog.setAction(action);
        auditLog.setResource(resource);
        auditLog.setDetails(details);
        auditLog.setIpAddress(getCurrentUserIpAddress());
        auditLog.setUserAgent(getCurrentUserAgent());

        auditLogRepository.save(auditLog);
    }
}
```

## Backup and Disaster Recovery

### Backup Strategy

#### Automated RDS Backups

```hcl
# RDS instance with automated backups
resource "aws_db_instance" "main" {
  # ... other configuration

  # Automated backups
  backup_retention_period = var.environment == "prod" ? 30 : 7
  backup_window          = "03:00-04:00"  # UTC
  copy_tags_to_snapshot  = true
  delete_automated_backups = false

  # Point-in-time recovery
  enabled_cloudwatch_logs_exports = ["error", "general", "slow-query"]

  # Final snapshot
  final_snapshot_identifier = "${var.environment}-db-final-snapshot-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  skip_final_snapshot      = var.environment == "dev" ? true : false

  # Cross-region backup
  dynamic "restore_to_point_in_time" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      restore_time = "2023-01-01T00:00:00Z"  # Example
    }
  }
}

# Cross-region snapshot copy
resource "aws_db_snapshot_copy" "cross_region" {
  count = var.environment == "prod" ? 1 : 0

  source_db_snapshot_identifier = aws_db_instance.main.latest_restorable_time
  target_db_snapshot_identifier = "${var.environment}-cross-region-backup-${formatdate("YYYYMMDD", timestamp())}"

  kms_key_id = var.kms_key_id

  tags = {
    Name        = "${var.environment}-cross-region-backup"
    Environment = var.environment
  }
}
```

#### S3 Backup Configuration

```hcl
# S3 bucket for backups
resource "aws_s3_bucket" "backups" {
  bucket = "careconnect-${var.environment}-backups"

  tags = {
    Name        = "careconnect-${var.environment}-backups"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "backups" {
  bucket = aws_s3_bucket.backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  bucket = aws_s3_bucket.backups.bucket

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.backups.arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  bucket = aws_s3_bucket.backups.id

  rule {
    id     = "database_backups"
    status = "Enabled"

    filter {
      prefix = "database/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = 2557  # 7 years for HIPAA compliance
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
```

### Disaster Recovery Plan

#### RTO/RPO Requirements

- **Recovery Time Objective (RTO)**: 4 hours
- **Recovery Point Objective (RPO)**: 1 hour
- **Data Retention**: 7 years (HIPAA compliance)

#### DR Site Setup

```hcl
# DR region configuration
provider "aws" {
  alias  = "dr"
  region = var.dr_region
}

# DR VPC
module "vpc_dr" {
  source = "./modules/vpc"
  providers = {
    aws = aws.dr
  }

  environment = "${var.environment}-dr"
  vpc_cidr    = "10.1.0.0/16"
}

# DR RDS (read replica)
resource "aws_db_instance" "dr_replica" {
  provider = aws.dr

  identifier = "careconnect-${var.environment}-dr"

  replicate_source_db = aws_db_instance.main.identifier

  instance_class    = var.db_instance_class
  publicly_accessible = false

  auto_minor_version_upgrade = true
  backup_retention_period    = 7
  backup_window             = "03:00-04:00"

  tags = {
    Name        = "careconnect-${var.environment}-dr"
    Environment = var.environment
    Type        = "DR"
  }
}

# DR ECS cluster (minimal capacity)
module "ecs_dr" {
  source = "./modules/ecs"
  providers = {
    aws = aws.dr
  }

  environment = "${var.environment}-dr"
  vpc_id      = module.vpc_dr.vpc_id
  subnet_ids  = module.vpc_dr.private_subnet_ids

  cluster_name    = "careconnect-${var.environment}-dr"
  desired_count   = 0  # Scale up during disaster
  min_capacity    = 0
  max_capacity    = 10

  container_image = var.backend_container_image
  database_url    = aws_db_instance.dr_replica.endpoint
}
```

#### Disaster Recovery Runbook

```bash
#!/bin/bash
# scripts/disaster-recovery.sh

set -e

DR_REGION="us-west-2"
PRIMARY_REGION="us-east-1"
ENVIRONMENT="prod"

echo "Starting disaster recovery process..."

# Step 1: Promote DR database
echo "Promoting read replica to primary..."
aws rds promote-read-replica \
    --db-instance-identifier careconnect-${ENVIRONMENT}-dr \
    --region $DR_REGION

aws rds wait db-instance-available \
    --db-instance-identifier careconnect-${ENVIRONMENT}-dr \
    --region $DR_REGION

# Step 2: Scale up DR ECS service
echo "Scaling up DR ECS service..."
aws ecs update-service \
    --cluster careconnect-${ENVIRONMENT}-dr \
    --service careconnect-${ENVIRONMENT}-dr-service \
    --desired-count 3 \
    --region $DR_REGION

aws ecs wait services-stable \
    --cluster careconnect-${ENVIRONMENT}-dr \
    --services careconnect-${ENVIRONMENT}-dr-service \
    --region $DR_REGION

# Step 3: Update DNS to point to DR site
echo "Updating DNS to DR site..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='careconnect.example.com.'].Id" \
    --output text | cut -d'/' -f3)

DR_ALB_DNS=$(aws elbv2 describe-load-balancers \
    --region $DR_REGION \
    --query "LoadBalancers[?contains(LoadBalancerName, 'careconnect-${ENVIRONMENT}-dr')].DNSName" \
    --output text)

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file://<(cat <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "api.careconnect.example.com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [
          {
            "Value": "$DR_ALB_DNS"
          }
        ]
      }
    }
  ]
}
EOF
)

# Step 4: Verify DR site
echo "Verifying DR site..."
sleep 60  # Wait for DNS propagation

curl -f https://api.careconnect.example.com/actuator/health

echo "Disaster recovery completed successfully!"

# Step 5: Notify stakeholders
curl -X POST $SLACK_WEBHOOK_URL \
    -H 'Content-type: application/json' \
    --data '{"text":"🚨 Disaster recovery activated. Site is now running from DR region."}'
```

### Recovery Testing

#### Monthly DR Tests

```bash
#!/bin/bash
# scripts/dr-test.sh

set -e

echo "Starting monthly DR test..."

# Create test environment in DR region
terraform workspace new dr-test
terraform plan -var-file="environments/dr-test.tfvars"
terraform apply -auto-approve

# Run smoke tests against DR environment
./scripts/smoke-tests.sh https://dr-test.careconnect.example.com

# Generate DR test report
echo "DR Test Results:" > dr-test-report.txt
echo "Date: $(date)" >> dr-test-report.txt
echo "RTO Achieved: $(cat rto-time.txt)" >> dr-test-report.txt
echo "RPO Achieved: $(cat rpo-time.txt)" >> dr-test-report.txt

# Cleanup test environment
terraform destroy -auto-approve
terraform workspace delete dr-test

echo "DR test completed successfully"
```

## Performance Optimization

### Database Optimization

#### Query Optimization

```sql
-- Analyze slow queries
SELECT
    query,
    calls,
    total_exec_time,
    mean_exec_time,
    rows
FROM pg_stat_statements
WHERE total_exec_time > 1000  -- queries taking more than 1 second total
ORDER BY total_exec_time DESC
LIMIT 20;

-- Optimize frequently accessed tables
ANALYZE users, vital_signs, medications;

-- Add missing indexes
CREATE INDEX CONCURRENTLY idx_vital_signs_user_type_date
ON vital_signs(user_id, type, measurement_time DESC);

CREATE INDEX CONCURRENTLY idx_messages_conversation_unread
ON messages(conversation_id, is_read, created_at DESC);

-- Partition large tables (PostgreSQL 12+ declarative partitioning)
CREATE TABLE vital_signs_partitioned (
    LIKE vital_signs INCLUDING ALL
) PARTITION BY RANGE (measurement_time);

CREATE TABLE vital_signs_2023 PARTITION OF vital_signs_partitioned
    FOR VALUES FROM ('2023-01-01') TO ('2024-01-01');
CREATE TABLE vital_signs_2024 PARTITION OF vital_signs_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE vital_signs_2025 PARTITION OF vital_signs_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

#### Connection Pooling

```properties
# application-prod.properties

# HikariCP configuration
spring.datasource.hikari.connection-timeout=20000
spring.datasource.hikari.idle-timeout=300000
spring.datasource.hikari.max-lifetime=1200000
spring.datasource.hikari.maximum-pool-size=20
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.pool-name=CareConnectHikariPool

# Connection validation
spring.datasource.hikari.connection-test-query=SELECT 1
spring.datasource.hikari.validation-timeout=5000

# Performance monitoring
spring.datasource.hikari.register-mbeans=true
```

### Caching Strategy

#### Redis Configuration

```yaml
# Redis cluster configuration
spring:
  redis:
    cluster:
      nodes:
        - prod-cache-001.region.cache.amazonaws.com:6379
        - prod-cache-002.region.cache.amazonaws.com:6379
        - prod-cache-003.region.cache.amazonaws.com:6379
    timeout: 2000ms
    lettuce:
      pool:
        max-active: 20
        max-idle: 5
        min-idle: 0
        time-between-eviction-runs: 60s
```

#### Cache Implementation

```java
@Service
public class CachedHealthService {

    @Cacheable(value = "userVitals", key = "#userId", unless = "#result.isEmpty()")
    public List<VitalSignDTO> getVitalSigns(Long userId) {
        return healthRepository.findByUserIdOrderByMeasurementTimeDesc(userId)
            .stream()
            .map(this::convertToDTO)
            .collect(Collectors.toList());
    }

    @CacheEvict(value = "userVitals", key = "#userId")
    public VitalSignDTO recordVitalSign(Long userId, VitalSignRequest request) {
        // Implementation
    }

    @Cacheable(value = "healthSummary", key = "#userId")
    public HealthSummaryDTO getHealthSummary(Long userId) {
        // Expensive aggregation query
    }

    @CacheEvict(value = {"userVitals", "healthSummary"}, key = "#userId")
    public void evictUserCache(Long userId) {
        // Manual cache eviction
    }
}
```

### CDN Optimization

#### CloudFront Configuration

```hcl
resource "aws_cloudfront_distribution" "main" {
  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.frontend.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    }
  }

  # API origin
  origin {
    domain_name = aws_lb.main.dns_name
    origin_id   = "ALB-${aws_lb.main.name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Static assets caching
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.frontend.id}"
    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400    # 1 day
    max_ttl     = 31536000 # 1 year
  }

  # API caching
  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALB-${aws_lb.main.name}"
    compress         = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type"]
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "https-only"
    min_ttl               = 0
    default_ttl           = 0
    max_ttl               = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.main.arn
    ssl_support_method  = "sni-only"
  }

  web_acl_id = aws_wafv2_web_acl.main.arn

  tags = {
    Name = "careconnect-${var.environment}-cdn"
  }
}
```

## Scaling Strategies

### Horizontal Scaling

#### Auto Scaling Configuration

```hcl
# ECS Auto Scaling
resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_capacity
  min_capacity       = var.min_capacity
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  tags = {
    Name = "${var.cluster_name}-scaling-target"
  }
}

# CPU-based scaling
resource "aws_appautoscaling_policy" "ecs_cpu" {
  name               = "${var.cluster_name}-cpu-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# Memory-based scaling
resource "aws_appautoscaling_policy" "ecs_memory" {
  name               = "${var.cluster_name}-memory-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = 80.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60
  }
}

# Custom metric scaling (API request rate)
resource "aws_appautoscaling_policy" "ecs_requests" {
  name               = "${var.cluster_name}-requests-scaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      metric_name = "RequestCountPerTarget"
      namespace   = "AWS/ApplicationELB"
      statistic   = "Sum"

      dimensions = {
        TargetGroup  = aws_lb_target_group.main.arn_suffix
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
    target_value = 1000.0
  }
}
```

### Database Scaling

#### Read Replicas

```hcl
# Read replica for reporting
resource "aws_db_instance" "read_replica" {
  identifier = "careconnect-${var.environment}-read-replica"

  replicate_source_db = aws_db_instance.main.identifier

  instance_class         = var.read_replica_instance_class
  publicly_accessible    = false
  auto_minor_version_upgrade = true

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  tags = {
    Name        = "careconnect-${var.environment}-read-replica"
    Environment = var.environment
    Type        = "ReadReplica"
  }
}

# Connection routing in application
@Configuration
public class DatabaseConfig {

    @Bean
    @Primary
    public DataSource primaryDataSource() {
        return DataSourceBuilder.create()
            .url("jdbc:postgresql://prod-db.region.rds.amazonaws.com:5432/careconnect")
            .username("careconnect_app")
            .password("${spring.datasource.password}")
            .build();
    }

    @Bean
    public DataSource readOnlyDataSource() {
        return DataSourceBuilder.create()
            .url("jdbc:postgresql://prod-db-read-replica.region.rds.amazonaws.com:5432/careconnect")
            .username("careconnect_readonly")
            .password("${spring.datasource.readonly.password}")
            .build();
    }

    @Bean
    public JdbcTemplate readOnlyJdbcTemplate() {
        return new JdbcTemplate(readOnlyDataSource());
    }
}
```

## Maintenance Procedures

### Scheduled Maintenance

#### Maintenance Window Planning

```bash
#!/bin/bash
# scripts/maintenance-window.sh

set -e

MAINTENANCE_START=$(date)
CLUSTER_NAME="careconnect-prod"
SERVICE_NAME="careconnect-prod-service"

echo "Starting maintenance window: $MAINTENANCE_START"

# 1. Enable maintenance mode
echo "Enabling maintenance mode..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service maintenance-service \
    --desired-count 1

# 2. Scale down main service
echo "Scaling down main service..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service $SERVICE_NAME \
    --desired-count 0

aws ecs wait services-stable \
    --cluster $CLUSTER_NAME \
    --services $SERVICE_NAME

# 3. Database maintenance
echo "Starting database maintenance..."

# Update RDS instance class if needed
if [ "$UPGRADE_DB_INSTANCE" = "true" ]; then
    aws rds modify-db-instance \
        --db-instance-identifier careconnect-prod-db \
        --db-instance-class $NEW_DB_INSTANCE_CLASS \
        --apply-immediately

    aws rds wait db-instance-available \
        --db-instance-identifier careconnect-prod-db
fi

# Run database maintenance
psql -h prod-db.region.rds.amazonaws.com -U admin -d careconnect << EOF
VACUUM ANALYZE users;
VACUUM ANALYZE vital_signs;
VACUUM ANALYZE medications;
VACUUM ANALYZE allergies;
REINDEX DATABASE careconnect;
EOF

# 4. Update infrastructure if needed
if [ -f "infrastructure-updates.tf" ]; then
    echo "Applying infrastructure updates..."
    terraform plan -out=maintenance.tfplan
    terraform apply maintenance.tfplan
fi

# 5. Deploy application updates
if [ "$DEPLOY_NEW_VERSION" = "true" ]; then
    echo "Deploying new application version..."
    ./scripts/blue-green-deploy.sh
else
    # Scale service back up
    echo "Scaling service back up..."
    aws ecs update-service \
        --cluster $CLUSTER_NAME \
        --service $SERVICE_NAME \
        --desired-count 3

    aws ecs wait services-stable \
        --cluster $CLUSTER_NAME \
        --services $SERVICE_NAME
fi

# 6. Disable maintenance mode
echo "Disabling maintenance mode..."
aws ecs update-service \
    --cluster $CLUSTER_NAME \
    --service maintenance-service \
    --desired-count 0

# 7. Run post-maintenance tests
echo "Running post-maintenance tests..."
./scripts/smoke-tests.sh

MAINTENANCE_END=$(date)
echo "Maintenance window completed: $MAINTENANCE_END"

# 8. Generate maintenance report
cat << EOF > maintenance-report-$(date +%Y%m%d).txt
Maintenance Window Report
========================

Start Time: $MAINTENANCE_START
End Time: $MAINTENANCE_END
Duration: $(($(date -d "$MAINTENANCE_END" +%s) - $(date -d "$MAINTENANCE_START" +%s))) seconds

Activities Performed:
- Database optimization: $(if [ "$DB_OPTIMIZED" = "true" ]; then echo "Completed"; else echo "Skipped"; fi)
- Infrastructure updates: $(if [ -f "infrastructure-updates.tf" ]; then echo "Applied"; else echo "None"; fi)
- Application deployment: $(if [ "$DEPLOY_NEW_VERSION" = "true" ]; then echo "Deployed"; else echo "Skipped"; fi)

Post-maintenance test results: $(if ./scripts/smoke-tests.sh > /dev/null 2>&1; then echo "Passed"; else echo "Failed"; fi)
EOF

echo "Maintenance report generated: maintenance-report-$(date +%Y%m%d).txt"
```

### System Updates

#### Security Patching

```bash
#!/bin/bash
# scripts/security-patching.sh

set -e

echo "Starting security patching process..."

# 1. Check for available security updates
echo "Checking for security updates..."

# Update base Docker images
docker pull openjdk:17-jdk-slim
docker pull postgres:15

# Check for OS-level patches (for EC2 instances if any)
yum list-security --security 2>/dev/null || true

# 2. Update dependencies
echo "Updating application dependencies..."

# Backend dependencies
cd backend/core
./mvnw versions:display-dependency-updates
./mvnw versions:use-latest-versions -DallowSnapshots=false
./mvnw clean test  # Ensure tests still pass

# Frontend dependencies
cd ../../frontend
flutter pub upgrade
flutter test

# 3. Build new container images
echo "Building updated container images..."

cd ../backend/core
docker build -t careconnect-backend:security-patch-$(date +%Y%m%d) .

# 4. Deploy to staging first
echo "Deploying to staging for testing..."
./scripts/deploy-staging.sh security-patch-$(date +%Y%m%d)

# 5. Run security tests
echo "Running security tests..."
./scripts/security-tests.sh staging

# 6. Deploy to production if tests pass
if [ $? -eq 0 ]; then
    echo "Security tests passed. Deploying to production..."
    ./scripts/blue-green-deploy.sh security-patch-$(date +%Y%m%d)
else
    echo "Security tests failed. Aborting production deployment."
    exit 1
fi

echo "Security patching completed successfully."
```

## Troubleshooting Production Issues

This section provides systematic approaches to diagnosing and resolving common production issues in the CareConnect platform. Each issue follows a structured format: **Problem** → **Root Causes** → **Diagnostic Steps** → **Resolution** → **Prevention**, enabling both quick fixes during incidents and long-term improvements to prevent recurrence.

### Common Issues and Systematic Solutions

#### Problem: ECS Tasks Fail to Start or Immediately Exit

**Symptoms**: 
- New deployments show tasks starting but immediately transitioning to STOPPED state
- CloudWatch Logs show containers exiting with non-zero exit codes
- ALB health checks report unhealthy targets
- Users experience 503 Service Unavailable errors

**Root Causes**:
This issue typically stems from one of several configuration or dependency problems:

1. **Environment Variable Misconfiguration**: Missing or incorrect environment variables (database URL, API keys, JWT secrets) cause application startup failures
2. **Database Connectivity Issues**: Application can't reach RDS due to security group rules, subnet configuration, or database being unavailable
3. **Container Image Problems**: ECR image is corrupt, missing dependencies, or built for wrong architecture (amd64 vs arm64)
4. **IAM Permission Errors**: ECS task lacks permissions to access Secrets Manager, S3, or other AWS services needed at startup
5. **Resource Constraints**: Task definition specifies insufficient memory/CPU, causing OOM kills during startup

**Systematic Diagnostic Steps**:

1. **Check ECS Task Exit Reason**:
   ```bash
   # Get detailed information about stopped tasks
   aws ecs describe-tasks \
       --cluster careconnect-prod \
       --tasks $(aws ecs list-tasks \
           --cluster careconnect-prod \
           --service-name careconnect-prod-service \
           --desired-status STOPPED \
           --query 'taskArns[0]' \
           --output text) \
       --query 'tasks[0].{StopReason:stoppedReason,ExitCode:containers[0].exitCode,LastStatus:lastStatus}'
   ```
   **What this tells you**: The exit code and stop reason often indicate the category of failure. Exit code 137 = OOM kill. Exit code 1 with "Essential container exited" = application crash.

2. **Examine Container Logs**:
   ```bash
   # View recent logs from failed containers
   aws logs filter-log-events \
       --log-group-name "/ecs/careconnect-prod" \
       --start-time $(date -d '10 minutes ago' +%s)000 \
       --query 'events[*].[timestamp,message]' \
       --output text | sort
   ```
   **What to look for**: 
   - "Connection refused" or "Connection timeout" = network/database issue
   - "Environment variable X not set" = configuration issue
   - "OutOfMemoryError" or "Killed" = resource constraint
   - Stack traces with "AccessDeniedException" = IAM permission issue

3. **Verify Task Definition Configuration**:
   ```bash
   # Review current task definition
   aws ecs describe-task-definition \
       --task-definition careconnect-backend \
       --query 'taskDefinition.{CPU:cpu,Memory:memory,Env:containerDefinitions[0].environment[*].name}' \
       --output json
   ```
   **What to check**: Ensure all required environment variables are present. Cross-reference with working configuration in staging.

4. **Test Database Connectivity from VPC**:
   ```bash
   # Launch a test container in same VPC/subnet to isolate network issues
   aws ecs run-task \
       --cluster careconnect-prod \
       --task-definition careconnect-test-connectivity \
       --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-xxx]}" \
       --launch-type FARGATE
   
   # Then exec into it and test database connection
   aws ecs execute-command \
       --cluster careconnect-prod \
       --task <task-id> \
       --container connectivity-test \
       --interactive \
       --command "/bin/sh"
   
   # Inside the container:
   nc -zv prod-db.region.rds.amazonaws.com 5432
   ```
   **What this proves**: If this succeeds but application fails, the issue is in application configuration, not network connectivity.

5. **Check Security Group Rules**:
   ```bash
   # Verify ECS tasks can reach RDS
   aws ec2 describe-security-groups \
       --filters "Name=group-name,Values=careconnect-prod-ecs-tasks" \
       --query 'SecurityGroups[0].IpPermissionsEgress[*]'
   
   # Verify RDS accepts connections from ECS
   aws ec2 describe-security-groups \
       --filters "Name=group-name,Values=careconnect-prod-rds" \
       --query 'SecurityGroups[0].IpPermissions[*]'
   ```
   **What to verify**: ECS security group allows outbound to port 5432. RDS security group allows inbound from ECS security group on port 5432.

**Resolution Steps**:

**If Environment Variable Missing**:
```bash
# Update task definition with missing variable
aws ecs register-task-definition \
    --cli-input-json file://updated-task-def.json

# Force new deployment to use updated task definition
aws ecs update-service \
    --cluster careconnect-prod \
    --service careconnect-prod-service \
    --force-new-deployment
```

**If Database Connectivity Issue**:
```bash
# Add rule to RDS security group allowing ECS tasks
aws ec2 authorize-security-group-ingress \
    --group-id sg-rds-id \
    --protocol tcp \
    --port 5432 \
    --source-group sg-ecs-tasks-id
```

**If Resource Constraint**:
```bash
# Update task definition with more resources
# Modify task-def.json: increase "memory": "2048" to "4096"
aws ecs register-task-definition --cli-input-json file://task-def.json
aws ecs update-service --cluster careconnect-prod --service careconnect-prod-service --task-definition careconnect-backend:NEW_REVISION
```

**If IAM Permission Missing**:
```bash
# Attach missing policy to ECS task role
aws iam attach-role-policy \
    --role-name careconnect-ecs-task-role \
    --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

**Prevention**:
- **Infrastructure as Code**: All task definitions and security groups should be in Terraform, reviewed in pull requests
- **Automated Testing**: CI/CD should deploy to staging and run health checks before allowing production deployment
- **Gradual Rollout**: Use blue-green or canary deployments so issues affect only a subset of traffic initially
- **Resource Monitoring**: Set up CloudWatch alarms for task stop reasons and OOM events

#### Problem: Database Connection Pool Exhaustion

**Symptoms**:
- Application logs show "Could not obtain connection from pool" errors
- Response times spike to >30 seconds
- Health checks start failing intermittently
- CloudWatch metrics show DatabaseConnections at or near maximum

**Root Causes**:
Connection pool issues occur when the application exhausts available database connections, usually due to:

1. **Connection Leaks**: Application code opens database connections but doesn't properly close them in exception paths
2. **Slow Queries**: Long-running queries hold connections for extended periods, starving the pool
3. **Traffic Spikes**: Sudden increase in traffic creates more concurrent requests than pool can handle
4. **Misconfigured Pool Size**: Pool max size is too small for the number of ECS tasks and request concurrency
5. **Database Performance**: Database is CPU-bound or experiencing high I/O wait, slowing all queries

**Systematic Diagnostic Steps**:

1. **Check Current Database Connections**:
   ```bash
   # Connect to RDS and query active connections
   psql -h prod-db.region.rds.amazonaws.com -U admin -d careconnect -c "
       SELECT 
           state, 
           COUNT(*) as count,
           MAX(EXTRACT(EPOCH FROM (now() - state_change))) as max_duration_seconds
       FROM pg_stat_activity 
       WHERE datname = 'careconnect'
       GROUP BY state
       ORDER BY count DESC;
   "
   ```
   **What to look for**: High count of "idle in transaction" (connection leak) or "active" queries with very long durations (slow queries).

2. **Identify Long-Running Queries**:
   ```bash
   psql -h prod-db.region.rds.amazonaws.com -U admin -d careconnect -c "
       SELECT 
           pid,
           usename,
           state,
           query,
           now() - state_change as duration
       FROM pg_stat_activity
       WHERE state != 'idle'
         AND now() - state_change > interval '30 seconds'
       ORDER BY duration DESC;
   "
   ```
   **What this reveals**: Specific queries that are holding connections for excessive time.

3. **Check HikariCP Metrics** (from application logs):
   ```bash
   aws logs filter-log-events \
       --log-group-name "/ecs/careconnect-prod" \
       --filter-pattern "HikariPool" \
       --start-time $(date -d '1 hour ago' +%s)000 \
       | jq -r '.events[].message' \
       | grep -E "active|idle|waiting"
   ```
   **What to look for**: Messages like "Thread starvation or clock leap detected" or "Total connections X (active Y, idle 0, waiting Z)".

**Resolution Steps**:

**Immediate (During Incident)**:
```bash
# 1. Scale up ECS tasks temporarily to distribute load
aws ecs update-service \
    --cluster careconnect-prod \
    --service careconnect-prod-service \
    --desired-count 10  # Double current count

# 2. Kill problematic long-running queries
psql -h prod-db.region.rds.amazonaws.com -U admin -d careconnect -c "
    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE state = 'active'
      AND now() - state_change > interval '5 minutes';
"

# 3. Restart ECS tasks to clear connection pools
aws ecs update-service \
    --cluster careconnect-prod \
    --service careconnect-prod-service \
    --force-new-deployment
```

**Long-Term (Post-Incident)**:
1. **Increase Connection Pool Size**: 
   Update `application.properties`:
   ```properties
   spring.datasource.hikari.maximum-pool-size=20  # Was 10
   spring.datasource.hikari.connection-timeout=30000
   ```

2. **Fix Connection Leaks**: 
   Review application code for improper connection handling. Ensure all `@Transactional` methods complete successfully or use try-with-resources for manual connection management.

3. **Optimize Slow Queries**:
   ```sql
   -- Add missing indexes identified in query analysis
   CREATE INDEX idx_vital_signs_user_time ON vital_signs(user_id, measurement_time DESC);
   ```

**Prevention**:
- **Connection Pool Monitoring**: Set up CloudWatch alarm when active connections > 80% of max
- **Query Performance Monitoring**: Use pg_stat_statements to track slow queries over time
- **Load Testing**: Regular load tests identify connection pool limits before production traffic hits them
- **Code Reviews**: Require review of all database access patterns for proper connection lifecycle management

```bash
# Check ALB metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApplicationELB \
    --metric-name TargetResponseTime \
    --dimensions Name=LoadBalancer,Value=app/careconnect-prod/1234567890abcdef \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Average,Maximum

# Check ECS service CPU/Memory usage
aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name CPUUtilization \
    --dimensions Name=ServiceName,Value=careconnect-prod-service Name=ClusterName,Value=careconnect-prod \
    --start-time $(date -d '1 hour ago' --iso-8601) \
    --end-time $(date --iso-8601) \
    --period 300 \
    --statistics Average,Maximum

# Analyze application logs for slow queries
aws logs filter-log-events \
    --log-group-name "/ecs/careconnect-prod" \
    --filter-pattern "Query took longer than" \
    --start-time $(date -d '1 hour ago' +%s)000
```

### Diagnostic Tools

#### Health Check Script

```bash
#!/bin/bash
# scripts/health-check.sh

set -e

echo "Running comprehensive health check..."

# 1. API Health Check
echo "Checking API health..."
API_HEALTH=$(curl -s https://api.careconnect.example.com/actuator/health)
if echo "$API_HEALTH" | grep -q '"status":"UP"'; then
    echo "✅ API is healthy"
else
    echo "❌ API is unhealthy: $API_HEALTH"
    exit 1
fi

# 2. Database Health Check
echo "Checking database connectivity..."
DB_CHECK=$(PGPASSWORD=$DB_PASSWORD psql -h prod-db.region.rds.amazonaws.com \
               -U careconnect_app \
               -d careconnect \
               -c "SELECT 1" 2>&1)
if [ $? -eq 0 ]; then
    echo "✅ Database is accessible"
else
    echo "❌ Database connection failed: $DB_CHECK"
    exit 1
fi

# 3. Cache Health Check
echo "Checking Redis connectivity..."
REDIS_CHECK=$(redis-cli -h prod-cache.region.cache.amazonaws.com ping 2>&1)
if [ "$REDIS_CHECK" = "PONG" ]; then
    echo "✅ Redis is responding"
else
    echo "❌ Redis connection failed: $REDIS_CHECK"
    exit 1
fi

# 4. ECS Service Health Check
echo "Checking ECS service status..."
RUNNING_TASKS=$(aws ecs describe-services \
    --cluster careconnect-prod \
    --services careconnect-prod-service \
    --query 'services[0].runningCount' \
    --output text)

DESIRED_TASKS=$(aws ecs describe-services \
    --cluster careconnect-prod \
    --services careconnect-prod-service \
    --query 'services[0].desiredCount' \
    --output text)

if [ "$RUNNING_TASKS" -eq "$DESIRED_TASKS" ]; then
    echo "✅ All ECS tasks are running ($RUNNING_TASKS/$DESIRED_TASKS)"
else
    echo "❌ ECS tasks mismatch: $RUNNING_TASKS/$DESIRED_TASKS running"
fi

# 5. Load Balancer Health Check
echo "Checking load balancer target health..."
HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
    --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/careconnect-prod/1234567890abcdef \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
    --output text)

if [ "$HEALTHY_TARGETS" -gt 0 ]; then
    echo "✅ Load balancer has $HEALTHY_TARGETS healthy targets"
else
    echo "❌ No healthy targets in load balancer"
    exit 1
fi

# 6. SSL Certificate Check
echo "Checking SSL certificate validity..."
SSL_EXPIRY=$(echo | openssl s_client -servername careconnect.example.com -connect careconnect.example.com:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
SSL_EXPIRY_EPOCH=$(date -d "$SSL_EXPIRY" +%s)
CURRENT_EPOCH=$(date +%s)
DAYS_UNTIL_EXPIRY=$(( ($SSL_EXPIRY_EPOCH - $CURRENT_EPOCH) / 86400 ))

if [ "$DAYS_UNTIL_EXPIRY" -gt 30 ]; then
    echo "✅ SSL certificate is valid for $DAYS_UNTIL_EXPIRY more days"
else
    echo "⚠️  SSL certificate expires in $DAYS_UNTIL_EXPIRY days"
fi

echo "Health check completed successfully!"
```

---

*This deployment and operations guide provides comprehensive instructions for managing the CareConnect platform in production. Regular updates to this document ensure operational procedures remain current with infrastructure changes.*

*Last Updated: October 2025*
*Version: 2025.1.0*