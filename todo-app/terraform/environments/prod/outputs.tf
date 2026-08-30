output "lightsail_public_ip" {
  value = module.lightsail.public_ip
}
output "ecr_repository_url" {
  value = module.ecr.repository_url
}
output "github_role_arn" {
  value = module.oidc.github_role_arn
}
