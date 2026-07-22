variable "cluster_name" {
  description = "Name of the EKS cluster that will use this VPC -- needed for the subnet tags EKS/ALB Controller require"
  type        = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  description = "Two availability zones (EKS requires subnets in at least 2 AZs)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.11.0/24"]
}
