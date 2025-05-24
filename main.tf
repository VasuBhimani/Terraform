provider "aws" {
  region = "us-east-1"
}

# Fetch default VPC and subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for EC2 allowing traffic from ALB and SSH
resource "aws_security_group" "ec2_sg" {
  name        = "ec2-sg"
  description = "Allow inbound from ALB on 5000 and SSH from anywhere"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow ALB on port 5000"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
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

# Security group for ALB allowing inbound HTTP (port 80)
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP inbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
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

# Launch Template with User Data to clone & run Python app on port 5000
resource "aws_launch_template" "flask_template" {
  name_prefix   = "flask-lt-"
  image_id      = "ami-0c02fb55956c7d316" # Amazon Linux 2
  instance_type = "t2.micro"

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y git python3

              cd /home/ec2-user
              git clone https://github.com/your-username/your-python-project.git
              cd your-python-project
              pip3 install -r requirements.txt

              # Make sure app.py binds 0.0.0.0:5000
              nohup python3 app.py > app.log 2>&1 &
              EOF
            )
}

# Auto Scaling Group in default subnets using launch template
resource "aws_autoscaling_group" "flask_asg" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.flask_template.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  force_delete              = true
  wait_for_capacity_timeout = "0"

  tag {
    key                 = "Name"
    value               = "flask-asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }

  # Attach instances to target group below
  target_group_arns = [aws_lb_target_group.flask_tg.arn]
}

# Application Load Balancer
resource "aws_lb" "flask_alb" {
  name               = "flask-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# Target Group for ALB to forward to instances on port 5000
resource "aws_lb_target_group" "flask_tg" {
  name     = "flask-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
  health_check {
    path                = "/"
    port                = "5000"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
}

# ALB Listener for HTTP (80) forwarding to target group
resource "aws_lb_listener" "flask_listener" {
  load_balancer_arn = aws_lb.flask_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.flask_tg.arn
  }
}

# Output the ALB DNS name to access the Flask app
output "flask_app_url" {
  description = "URL to access the Flask app via ALB"
  value       = "http://${aws_lb.flask_alb.dns_name}"
}
