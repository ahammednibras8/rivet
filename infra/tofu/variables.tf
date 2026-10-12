variable "bootstrap_ipv4_cidr" {
  description = "Single IPv4 /32 temporarily allowed for initial Tailscale bootstrap; defaults to an unroutable TEST-NET-1 address."
  type        = string
  default     = "192.0.2.1/32"
  nullable    = false

  validation {
    condition = (
      var.bootstrap_ipv4_cidr == trimspace(var.bootstrap_ipv4_cidr) &&
      can(cidrnetmask(var.bootstrap_ipv4_cidr)) &&
      can(regex("/32$", var.bootstrap_ipv4_cidr))
    )
    error_message = "bootstrap_ipv4_cidr must be one IPv4 address using /32 notation."
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
