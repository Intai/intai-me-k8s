packer {
  required_plugins {
    qemu = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/qemu"
    }
  }
}

source "qemu" "k8s-node" {
  iso_url          = var.ubuntu_iso_url
  iso_checksum     = var.ubuntu_iso_checksum
  disk_size        = var.disk_size
  format           = "qcow2"
  accelerator      = var.qemu_accelerator
  http_directory   = "http"
  vm_name          = "k8s-node.qcow2"
  output_directory = "output-k8s-node"

  cpus   = var.vm_cpus
  memory = var.vm_memory_mb

  boot_wait = "5s"
  boot_command = [
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds='nocloud;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/'<enter><wait>",
    "initrd /casper/initrd<enter><wait>",
    "boot<enter>"
  ]

  ssh_username           = "packer"
  ssh_password           = "packer"
  ssh_timeout            = "30m"
  ssh_handshake_attempts = 100
  shutdown_command       = "sudo shutdown -P now"

  headless = true
}

build {
  sources = ["source.qemu.k8s-node"]

  provisioner "ansible" {
    playbook_file = "../ansible/playbook-image.yml"
  }
}
