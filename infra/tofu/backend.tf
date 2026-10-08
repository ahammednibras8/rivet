terraform {
  backend "s3" {
    key          = "phase-1/rivet.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}
