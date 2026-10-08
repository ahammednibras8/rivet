output "workspace_instance_name" {
  description = "Stable Lightsail instance name used by operational commands."
  value       = aws_lightsail_instance.workspace.name
}

output "workspace_ipv4_address" {
  description = "Static public IPv4 address used by the authorized Ansible control node."
  value       = aws_lightsail_static_ip_attachment.workspace.ip_address
}

output "workspace_ssh_user" {
  description = "Administrative account created by the minimal cloud-init bridge."
  value       = "rivet-admin"
}
