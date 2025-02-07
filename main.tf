provider "aws" {
  region = "us-east-1"  # يمكنك تغيير المنطقة حسب الحاجة
}

# إنشاء VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

# إنشاء الإنترنت Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# إنشاء NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_1.id

  tags = {
    Name = "main-nat"
  }
}

# إنشاء Public Subnets
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-2"
  }
}

# إنشاء Private Subnets
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-subnet-2"
  }
}

# إنشاء Key Pair
resource "aws_key_pair" "my_key" {
  key_name   = "my-ec2-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDagkRCXXss65Q3PwinBlMnbb8uQrXtmwbqUnI+dpcDZlpDb/fonItAfZe7KnjF1CFUgOLK3nUc87u+hhDDwN54ZtxU3mF/ooparHBJGinct2tCeYAGUENF+8vWmn94v09DYlokAODt3lyEf2p1LkfEioQtUBHR0f5XP4z5M2nKpxcnciLKwLh68XEKsQGJMqqo6aeAV/0rkv0gwlQmqJAAGRsutl0xVT7qqMzL5bIGsorm4fZCj8oNR0mg1tdmt9YDs8/nIELhy2sdkxSed2879knv612trOYm1sHB4Z5qvsfEXYIVb9LQzkryJoztXnm4YE86A8R+k5cyiZMKkD79 ec2-user@ip-172-31-28-4.ec2.internal"  # يجب عليك وضع المفتاح العام هنا
}

# إنشاء Security Groups للـ EC2 و Load Balancer
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  ingress {
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

resource "aws_security_group" "lb_sg" {
  vpc_id = aws_vpc.main.id

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

# إنشاء Load Balancer
resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  tags = {
    Name = "main-lb"
  }
}

# إنشاء Target Group
resource "aws_lb_target_group" "main" {
  name     = "main-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    interval            = 30
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }

  tags = {
    Name = "main-target-group"
  }
}

# إنشاء Listener لـ Load Balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# إنشاء Launch Template لـ EC2
resource "aws_launch_template" "web_lt" {
  name          = "web-lt"
  image_id      = "ami-0c104f6f4a5d9d1d5"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.my_key.key_name  # استخدام Key Pair الذي تم إنشاؤه
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data     = base64encode(<<-EOF
                  #!/bin/bash
                  sudo apt update -y
                  sudo apt install apache2 -y
                  sudo systemctl start apache2
                  sudo systemctl enable apache2
                  EOF
  )
}

# إنشاء Auto Scaling Group
resource "aws_autoscaling_group" "web_asg" {
  vpc_zone_identifier = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  desired_capacity    = 2
  max_size            = 4
  min_size            = 2

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.main.arn]
}

# إنشاء CloudWatch Metric Alarm
resource "aws_cloudwatch_metric_alarm" "high_traffic" {
  alarm_name          = "high-traffic-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "RequestCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "Trigger scaling when requests exceed 1000 per minute."
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    LoadBalancer = aws_lb.main.id
  }
}

# إنشاء Auto Scaling Policy
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name  = aws_autoscaling_group.web_asg.name
}
