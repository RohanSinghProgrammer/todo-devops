# Server Setup Guide

This guide covers how to set up the Nginx reverse proxy on your server for the Todo application.

## Prerequisites
1. You have a server with Nginx installed (`sudo apt install nginx` on Ubuntu/Debian).
2. You have copied `nginx-reverse-proxy.conf` from this project to your server.
3. You have started your containerized application mapping to port 3000 (e.g., `podman run -d -p 3000:8080 --name todo-app todo-app-secure`).

## Nginx Setup Instructions

1. **Copy the Configuration**
   Copy the provided configuration file into your server's Nginx `sites-available` directory:
   ```bash
   sudo cp nginx-reverse-proxy.conf /etc/nginx/sites-available/todo-app
   ```

2. **Enable the Site**
   Enable the site by creating a symbolic link to the `sites-enabled` directory:
   ```bash
   sudo ln -s /etc/nginx/sites-available/todo-app /etc/nginx/sites-enabled/
   ```

3. **Test the Configuration**
   Test the Nginx configuration to make sure there are no syntax errors before reloading:
   ```bash
   sudo nginx -t
   ```

4. **Reload Nginx**
   If the test passes successfully, reload Nginx to apply the new configuration:
   ```bash
   sudo systemctl reload nginx
   ```

## DNS and SSL (HTTPS)

- **DNS**: Make sure you have configured your domain's DNS records (A Record) to point `todo.utilsfirst.com` to your server's public IP address.
- **SSL (HTTPS)**: Once the site is accessible via HTTP, it is highly recommended to secure it with HTTPS. If you have Certbot installed, you can automate this by running:
  ```bash
  sudo certbot --nginx -d todo.utilsfirst.com
  ```
