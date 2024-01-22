## Create service-account and grant it Administrator Access to run the GitLab pipelines
resource "aws_iam_user" "service_account" {
  name = "Gitlab-service-account"
}

resource "aws_iam_access_key" "service_account_access_key" {
  user = aws_iam_user.service_account.name
}

resource "aws_iam_user_policy_attachment" "service_account_attachment" {
  user       = aws_iam_user.service_account.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Create VPC
resource "aws_vpc" "eks_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "eks-vpc"
  }
}

# Create Subnets
resource "aws_subnet" "private_subnets" {
  count = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"], count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b", "us-east-1c"], count.index)
  map_public_ip_on_launch = false

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "public_subnets" {
  count = 3
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = element(["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"], count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b", "us-east-1c"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# IAM Role Policy Attachment for EKS Cluster
resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Create EKS Cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eks_cluster_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = concat(aws_subnet.private_subnets[*].id, aws_subnet.public_subnets[*].id)
  }

  depends_on = [aws_vpc.eks_vpc]
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "eks_node_group" {
  name = "eks-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# IAM Role WorkerNode Policy Attachment for EKS Node Group
resource "aws_iam_role_policy_attachment" "eks_node_group_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

# IAM Role CNI Policy Attachment for EKS Node Group
resource "aws_iam_role_policy_attachment" "eks_cni_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

# IAM Role ECR Policy Attachment for EKS Node Group
resource "aws_iam_role_policy_attachment" "eks_ec2_policy_attachment" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# Create EKS Node Group (Private Node Pool)
resource "aws_eks_node_group" "private_node_group" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  node_group_name = "private-node-group"
  subnet_ids = aws_subnet.private_subnets[*].id
  node_role_arn = aws_iam_role.eks_node_group.arn
  instance_types = ["t3.small"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [aws_eks_cluster.my_cluster,
  aws_iam_role_policy_attachment.eks_node_group_policy_attachment,
  aws_iam_role_policy_attachment.eks_cni_policy_attachment,
  aws_iam_role_policy_attachment.eks_ec2_policy_attachment
  ]
}

# Create EKS Node Group (Public Node Pool)
resource "aws_eks_node_group" "public_node_group" {
  cluster_name = aws_eks_cluster.my_cluster.name
  node_group_name = "public-node-group"
  subnet_ids = aws_subnet.public_subnets[*].id
  node_role_arn = aws_iam_role.eks_node_group.arn
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 1
    max_size     = 3
    min_size     = 1
  }

  depends_on = [aws_eks_cluster.my_cluster,
  aws_iam_role_policy_attachment.eks_node_group_policy_attachment,
  aws_iam_role_policy_attachment.eks_cni_policy_attachment,
  aws_iam_role_policy_attachment.eks_ec2_policy_attachment
  ]
}

# Random String for S3 Bucket Name Suffix
resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

# Create S3 Bucket to mount it into the cluster
resource "aws_s3_bucket" "eks_s3_bucket" {
  bucket = "eks-s3-bucket-${random_string.bucket_suffix.result}"
}

# Create Storage Class for EKS
resource "kubernetes_storage_class" "eks_storage_class" {
  metadata {
    name = "eks-sc"
  }

  storage_provisioner = "kubernetes.io/aws-ebs"
  parameters = {
    type             = "gp2"
    zones            = "us-east-1a,us-east-1b,us-east-1c"
    encrypted        = "true"
  }
}

# Create Persistent Volume (PV)
resource "kubernetes_persistent_volume" "eks_pv" {
  metadata {
    name = "eks-pv"
  }

  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes = ["ReadWriteOnce"]
    persistent_volume_source {
      vsphere_volume {
        volume_path = "/absolute/path"
      }
      aws_elastic_block_store {
      volume_id = aws_s3_bucket.eks_s3_bucket.id
      fs_type   = "ext4"
      }
    }
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name = kubernetes_storage_class.eks_storage_class.metadata[0].name
  }

}

# Create Persistent Volume Claim (PVC)
resource "kubernetes_persistent_volume_claim" "eks_pvc" {
  metadata {
    name = "eks-pvc"
  }

  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
    storage_class_name = kubernetes_storage_class.eks_storage_class.metadata[0].name
  }

}

# AWS RDS 
resource "aws_subnet" "rds_subnet" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.7.0/24"
  availability_zone       = "us-east-1a" 
}

resource "aws_security_group" "rds_security_group" {
  vpc_id = aws_vpc.eks_vpc.id
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.rds_subnet.id]
}

resource "random_password" "db_password" {
  length  = 16
  special = true
}

resource "aws_db_instance" "db_instance" {
  identifier           = "ML65-db"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  username             = "adminuser"
  password             = random_password.db_password.result
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_security_group.id]
}