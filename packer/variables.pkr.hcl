variable "ubuntu_iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
}

variable "vm_cpus" {
  type    = number
  default = 1
}

variable "vm_memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = string
  default = "20G"
}

variable "qemu_accelerator" {
  type    = string
  default = "kvm"
}
