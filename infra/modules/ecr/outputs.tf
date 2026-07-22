output "repository_urls" {
  description = "Map of repo name (e.g. \"api\") to its full ECR URL"
  value       = { for name, repo in aws_ecr_repository.repos : name => repo.repository_url }
}
