resource "aws_lightsail_instance_public_ports" "workspace" {
  instance_name = aws_lightsail_instance.workspace.name

  port_info {
    protocol          = "tcp"
    from_port         = 22
    to_port           = 22
    cidrs             = [var.operator_ipv4_cidr]
    ipv6_cidrs        = []
    cidr_list_aliases = []
  }
}