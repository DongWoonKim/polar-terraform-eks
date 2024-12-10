terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC 모듈 사용
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.vpc_name
  cidr = var.vpc_cidr

  azs             = var.availability_zones
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS를 위한 태그 추가
  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  tags = {
    Environment = var.environment
    Terraform   = "true"
  }
}

# EC2 인스턴스 생성
resource "aws_instance" "public_front_ec2" {
  ami           = var.ami_id                   # 사용하려는 AMI ID
  instance_type = var.instance_type            # EㅌC2 인스턴스 타입 (예: "t2.micro")
  subnet_id     = module.vpc.public_subnets[0] # Public Subnet 중 첫 번째 서브넷 사용

  associate_public_ip_address = true # Public IP 할당 (필수)

  security_groups = [aws_security_group.front_service_sg.id] # 보안 그룹 연결

  # EC2에서 실행할 초기 스크립트 (JDK 설치)
  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y openjdk-21-jdk  # JDK 21 설치
    java -version                       # JDK 버전 확인
  EOF

  tags = {
    Name        = "Front-Service-EC2"
    Environment = var.environment
  }
}


# Private Subnet EC2 생성 (MySQL)
resource "aws_instance" "mysql_ec2" {
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = module.vpc.private_subnets[0]

  associate_public_ip_address = false

  security_groups = [aws_security_group.mysql_sg.id]

  user_data = <<-EOF
    #!/bin/bash
    sudo apt update -y
    sudo apt install -y mysql-server
    sudo systemctl enable mysql
    sudo systemctl start mysql
  EOF

  tags = {
    Name        = "MySQL-EC2"
    Environment = var.environment
  }
}


# EKS 관련
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster_role.name
}

# Node Group IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = slice(module.vpc.private_subnets, 1, length(module.vpc.private_subnets))
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name        = "EKS-EC2"
    Environment = var.environment
  }
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = slice(module.vpc.private_subnets, 1, length(module.vpc.private_subnets))

  scaling_config {
    desired_size = var.node_group_desired_size
    max_size     = var.node_group_max_size
    min_size     = var.node_group_min_size
  }

  instance_types = var.node_instance_types

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy
  ]
}

# EKS Node Group 보안 그룹 (예시)
resource "aws_security_group" "eks_nodes_sg" {
  name        = "${var.cluster_name}-eks-nodes-sg"
  description = "EKS Node Group security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-eks-nodes-sg"
  }
}


# Public Subnet에 연결할 보안 그룹
resource "aws_security_group" "front_service_sg" {
  name        = "public-ec2-sg"
  description = "Security group for Public EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # 전 세계에서 SSH 접근 허용 (테스트 환경용, 운영 환경에서는 제한 필요)
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # HTTP 트래픽 허용
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # HTTPS 트래픽 허용
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # 모든 아웃바운드 트래픽 허용
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Public-FRONT-EC2-SG"
  }
}

# MySQL Security Group
resource "aws_security_group" "mysql_sg" {
  name        = "${var.cluster_name}-mysql-sg"
  description = "Allow access to MySQL from EKS nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow MySQL access from EKS nodes"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-mysql-sg"
  }
}
