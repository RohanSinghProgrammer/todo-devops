variable "repository_name" {
  type        = string
  description = "The name of the ECR repository"
}

variable "image_retention_days" {
  type        = number
  description = "Number of days to retain non-latest images in ECR before expiration"
  default     = 3
}
