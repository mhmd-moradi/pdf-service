# This is the trust foundation for IRSA: it lets AWS IAM trust tokens
# issued by THIS cluster's Kubernetes API, so a pod's ServiceAccount token
# can be exchanged for temporary AWS credentials without any static keys
# stored in the cluster. The EBS CSI driver and AWS Load Balancer
# Controller both need this; Phase 8 will use the same mechanism for the
# app's own AWS access (e.g. S3).

data "tls_certificate" "eks_oidc" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}
