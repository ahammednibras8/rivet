variable "operator_ssh_public_key" {
  type = string
}

locals {
  rendered_bootstrap = templatefile(
    "${path.module}/../../../infra/tofu/bootstrap.sh.tftpl",
    {
      operator_ssh_public_key = var.operator_ssh_public_key
    }
  )
}
