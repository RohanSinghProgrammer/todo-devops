output "public_ip" {
  value = aws_lightsail_static_ip.app_ip.ip_address
}

output "private_key" {
  value     = aws_lightsail_key_pair.app_key.private_key
  sensitive = true
}
