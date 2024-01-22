output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_id" {
  description = "Kubernetes Cluster Id"
  value       = aws_eks_cluster.eks_cluster.id
}

output "aws_access_key_id" {
  value = aws_iam_access_key.service_account_access_key.id
}

output "aws_secret_access_key" {
  value = aws_iam_access_key.service_account_access_key.secret
}

output "rds_username" {
  value = aws_db_instance.db_instance.username
}

output "rds_password" {
  value = random_password.db_password.result
}