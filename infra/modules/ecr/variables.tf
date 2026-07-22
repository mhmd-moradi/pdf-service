variable "repo_names" {
  description = "Names of the ECR repositories to create, e.g. [\"api\", \"worker\", \"frontend\"]"
  type        = list(string)
}

variable "prefix" {
  description = "Prepended to each repo name, e.g. \"pdf-service\" -> \"pdf-service-api\""
  type        = string
}

variable "image_retention_count" {
  description = "Keep only this many most-recent images per repo -- ECR storage isn't free, and a learning project doesn't need history"
  type        = number
  default     = 10
}
