resource "aws_lightsail_key_pair" "app_key" {
  name = "${var.instance_name}-key"
}

resource "aws_lightsail_instance" "app" {
  name              = var.instance_name
  availability_zone = var.availability_zone
  blueprint_id      = var.blueprint_id
  bundle_id         = var.bundle_id
  key_pair_name     = aws_lightsail_key_pair.app_key.name

  user_data = <<-EOF
              #!/bin/bash
              # Setup 2GB Swap Memory
              fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
              chmod 600 /swapfile
              mkswap /swapfile
              swapon /swapfile
              echo '/swapfile none swap sw 0 0' >> /etc/fstab

              # Install Docker
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              EOF
}

resource "aws_lightsail_static_ip" "app_ip" {
  name = "${var.instance_name}-ip"
}

resource "aws_lightsail_static_ip_attachment" "app_ip_attach" {
  static_ip_name = aws_lightsail_static_ip.app_ip.name
  instance_name  = aws_lightsail_instance.app.name
}

resource "aws_lightsail_instance_public_ports" "app_ports" {
  instance_name = aws_lightsail_instance.app.name

  port_info {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80
  }

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }
}
