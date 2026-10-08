locals {
  availability_zone = "ap-south-1a"
  blueprint_id      = "ubuntu_24_04"
  bundle_id         = "medium_3_0"

  instance_name  = "rivet-workspace"
  key_pair_name  = "rivet-operator"
  static_ip_name = "rivet-workspace-ip"
}
