variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "azs" {
  description = "Must be 2 AZs in the region above"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "github_repo" {
  description = "Your GitHub repo in the form \"username/pdf-service\", used to scope the GitHub Actions IAM role"
  type        = string
}
