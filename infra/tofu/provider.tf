provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      ManagedBy = "OpenTofu"
      Project   = "Rivet"
      Workspace = "primary"
    }
  }
}
