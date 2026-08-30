variable "aws_region" {
  default = "us-east-1"
}
variable "github_repository" {
  description = "The github org/repo for OIDC (e.g., myorg/myrepo)"
}
variable "key_pair_name" {
  description = "The name of the SSH key pair to attach to the Lightsail instance"
}
