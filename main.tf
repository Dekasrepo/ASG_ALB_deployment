
#Create a vpc
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
}

#Create public subnet 1
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-3a"

  tags = {
    Name = "public_subnet_1"
  }
}

#Create public subnet 2
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-3b"

  tags = {
    Name = "public_subnet_2"
  }

}

#Create public subnet 3
resource "aws_subnet" "public_subnet_3" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "eu-west-3c"

  tags = {
    Name = "public_subnet_3"
  }
}


#create an internet gateway 
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "igw"
  }
}

#Create a route table, edit routes and associate to internet gateway
resource "aws_route_table" "route" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

}

# Associate route table to public subnets - For demo purposes
resource "aws_route_table_association" "public_subnet_1_assoc" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.route.id
}

resource "aws_route_table_association" "public_subnet_2_assoc" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.route.id
}

resource "aws_route_table_association" "public_subnet_3_assoc" {
  subnet_id      = aws_subnet.public_subnet_3.id
  route_table_id = aws_route_table.route.id
}

#create security group for load balancer
resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "allow inbound traffic to alb"
  vpc_id      = aws_vpc.main_vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #open to the internet
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] #Allow outbound traffic
  }
  tags = {
    Name = "ALB_SG"
  }

}

# Security Group for Auto Scaling Group
resource "aws_security_group" "asg_sg" {
  vpc_id = aws_vpc.main_vpc.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] # Allow traffic from ALB
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ASG-SG"
  }
}

#Create security group for EC2 instance
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "allow ssh access to ec2"
  vpc_id      = aws_vpc.main_vpc.id


  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id] #Allow traffic from ALB
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] #For demo purposes
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "EC2_SG"
  }
}

#create a Load Balancer
resource "aws_lb" "main-lb" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id, aws_subnet.public_subnet_3.id]

  enable_deletion_protection = false


  tags = {
    Name = "Main-LB"
  }
}

#Create a Target Group for our Load Balancer
resource "aws_lb_target_group" "web-tg" {
  name        = "web-tg"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id

  health_check {
    path                = "/" # Ensures ALB checks if the root page is accessible
    interval            = 30
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 2
  }

  tags = {
    Name = "Web-TG"
  }
}

#create Listening Port for Load Balancer
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main-lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-tg.arn
  }
}

#Create EC2 launch template for ASG
resource "aws_launch_template" "asg_lt" {
  name_prefix   = "asg_lt"
  image_id      = "ami-06e02ae7bdac6b938"
  instance_type = "t2.micro"
  key_name      = "webserver"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "ASG-Instance"
    }
  }

  user_data = base64encode(<<-EOF
        #!/bin/bash
        sudo apt update -y
        sudo apt install apache2 -y
        sudo systemctl start apache2
        sudo systemctl enable apache2
        echo "Welcome to the HA webapp" > /var/www/html/index.html
        EOF
  )
}

#create Auto Scaling Group
resource "aws_autoscaling_group" "main_asg" {
  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id, aws_subnet.public_subnet_3.id]
  max_size            = "3"
  min_size            = "2"
  desired_capacity    = "2"

  launch_template {
    id      = aws_launch_template.asg_lt.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.web-tg.arn]
}

