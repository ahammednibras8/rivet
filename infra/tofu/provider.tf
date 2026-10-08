provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      ManagedBy = "OpenTofu"
      Phase     = "phase-1"
      Project   = "Rivet"
    }
  }
}