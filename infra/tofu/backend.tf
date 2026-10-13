terraform {
  backend "s3" {
    key          = "rivet/infrastructure.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
