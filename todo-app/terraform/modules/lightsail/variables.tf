variable "instance_name" {
  type = string
}
variable "availability_zone" {
  type = string
}
variable "blueprint_id" {
  type    = string
  default = "ubuntu_22_04"
}
variable "bundle_id" {
  type    = string
  default = "nano_3_1"
}

