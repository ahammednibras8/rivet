resource "aws_lightsail_key_pair" "operator" {
  name       = local.key_pair_name
  public_key = trimspace(var.operator_ssh_public_key)
}

resource "aws_lightsail_instance" "workspace" {
  name              = local.instance_name
  availability_zone = local.availability_zone
  blueprint_id      = local.blueprint_id
  bundle_id         = local.bundle_id
  key_pair_name     = aws_lightsail_key_pair.operator.name
  ip_address_type   = "ipv4"

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    operator_ssh_public_key = trimspace(var.operator_ssh_public_key)
  })

  tags = {
    Name = local.instance_name
  }

  lifecycle {
    prevent_destroy = true
  }
}
