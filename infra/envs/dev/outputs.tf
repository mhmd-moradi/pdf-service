output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this after apply to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "ecr_repository_urls" {
  value = module.ecr.repository_urls
}

output "lb_controller_role_arn" {
  description = "Use this to annotate the aws-load-balancer-controller ServiceAccount"
  value       = aws_iam_role.lb_controller.arn
}

output "github_actions_role_arn" {
  description = "Add this as a GitHub Actions secret/variable for the ECR-push workflow to assume"
  value       = aws_iam_role.github_actions.arn
}
