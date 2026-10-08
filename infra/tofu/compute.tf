resource "aws_lightsail_key_pair" "operator" {
  name       = local.key_pair_name
  public_key = trimspace(var.operator_ssh_public_key)
}