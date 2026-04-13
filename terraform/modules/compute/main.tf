data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-deployer"
  public_key = file("~/.ssh/id_rsa.pub")

  tags = {
    Name        = "${var.project_name}-deployer"
    Environment = var.environment
  }
}

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.deployer.key_name

  root_block_device {
    volume_size = var.vm_disk_gb + 15
    volume_type = "gp3"
    encrypted   = true
  }

  cpu_options {
    nested_virtualization = "enabled"
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = {
    Name        = "${var.project_name}-instance"
    Environment = var.environment
  }
}

resource "aws_eip" "main" {
  instance = aws_instance.main.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
  }
}
