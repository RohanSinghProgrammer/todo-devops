output "lightsail_public_ip" {
  value = module.lightsail.public_ip
}
output "lightsail_private_key" {
  value     = module.lightsail.private_key
  sensitive = true
}
output "ecr_repository_url" {
  value = module.ecr.repository_url
}
output "github_role_arn" {
  value = module.oidc.github_role_arn
}
