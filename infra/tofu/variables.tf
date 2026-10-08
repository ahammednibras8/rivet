variable "operator_ipv4_cidr" {
  description = "Single public IPv4 address allowed to reach SSH, written as a /32 CIDR."
  type        = string
  nullable    = false

  validation {
    condition = (
      var.operator_ipv4_cidr == trimspace(var.operator_ipv4_cidr) &&
      can(cidrnetmask(var.operator_ipv4_cidr)) &&
      can(regex("/32$", var.operator_ipv4_cidr))
    )
    error_message = "operator_ipv4_cidr must be one public IPv4 address using /32 notation."
  }
}

variable "operator_ssh_public_key" {
  description = "Existing RSA public key uploaded to Lightsail; never provide the private key."
  type        = string
  nullable    = false

  validation {
    condition = can(regex(
      "^ssh-rsa [A-Za-z0-9+/]+={0,2}( [^\\r\\n]+)?$",
      var.operator_ssh_public_key
    ))
    error_message = "operator_ssh_public_key must contain one OpenSSH RSA public key."
  }
}

variable "budget_notification_email" {
  description = "Private email address that receives Rivet AWS budget alerts."
  type        = string
  nullable    = false
  sensitive   = true

  validation {
    condition = can(regex(
      "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$",
      var.budget_notification_email
    ))
    error_message = "budget_notification_email must be a valid email address."
  }
}
