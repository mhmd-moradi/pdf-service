resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repo_names)

  name                 = "${var.prefix}-${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    # Free vulnerability scanning on every push -- worth having even for a
    # learning project, since this is a real (if small) security practice.
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "expire_old_images" {
  for_each   = aws_ecr_repository.repos
  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the ${var.image_retention_count} most recent images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
