output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

# Needed in Phase 8 for IRSA (IAM Roles for Service Accounts) -- the OIDC
# issuer URL is how AWS trusts a Kubernetes ServiceAccount's token.
output "cluster_oidc_issuer_url" {
  value = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  # Same as cluster_oidc_issuer_url but without the "https://" prefix --
  # this is the format IAM trust policies expect when referencing the
  # provider by URL (e.g. "${oidc_provider_url}:sub").
  value = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}
