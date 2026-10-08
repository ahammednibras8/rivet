variable "operator_ssh_public_key" {
  type = string
}

locals {
  rendered_cloud_init = templatefile(
    "${path.module}/../../../infra/tofu/cloud-init.yaml.tftpl",
    {
      operator_ssh_public_key = var.operator_ssh_public_key
    }
  )
  cloud_init = yamldecode(local.rendered_cloud_init)
}
