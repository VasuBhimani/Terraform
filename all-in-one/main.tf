# ------------------------
# Provider Configuration
# ------------------------
provider "aws" {
  region = var.aws_region
}

# ------------------------
# Use Local Variables
# ------------------------
locals {
  instance_name = "demo-instance"
}

# ------------------------
# Fetch Latest Amazon Linux 2 AMI (data source)
# ------------------------
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# ------------------------
# Create EC2 Key Pair
# ------------------------
resource "aws_key_pair" "deployer" {
  key_name   = "demo-key"
  public_key = file(var.public_key_path)
}

# ------------------------
# Create EC2 Security Group (allows SSH & HTTP)
# ------------------------
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow SSH and HTTP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------
# Create EC2 Instance
# ------------------------
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.allow_web.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum install -y python3 git
              git clone https://github.com/your/repo.git app
              cd app && pip3 install -r requirements.txt
              nohup python3 app.py &
              EOF

  tags = {
    Name = local.instance_name
  }

  # Run command to install Python and Flask app
  provisioner "remote-exec" {
    inline = [
      "sudo yum install -y python3 git",
      "git clone https://github.com/your/repo.git app",
      "cd app && pip3 install -r requirements.txt",
      "nohup python3 app.py &"
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file(var.private_key_path)
      host        = self.public_ip
    }
  }
}

# ------------------------
# Output EC2 Public IP
# ------------------------
output "ec2_public_ip" {
  value = aws_instance.web.public_ip
  description = "Use this IP to access the running app on port 5000"
}
