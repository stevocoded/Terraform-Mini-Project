provider "aws" {
  region  = "eu-west-2"
}

resource "aws_vpc" "VPC" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "VPC"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.VPC.id

  tags = {
    Name = "igw"
  }
}

resource "aws_route_table" "route-table" {
  vpc_id = aws_vpc.VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "route-table"
  }
}

resource "aws_subnet" "Public-subnet1" {
  vpc_id     = aws_vpc.VPC.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "eu-west-2a"
  tags = {
    Name = "Public-subnet1"
  }
}

resource "aws_subnet" "Public-subnet2" {
  vpc_id     = aws_vpc.VPC.id
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true
  availability_zone = "eu-west-2b"
  tags = {
    Name = "Public-subnet2"
  }
  
}

resource "aws_route_table_association" "route-table-subnet1-association" {
  subnet_id      = aws_subnet.Public-subnet1.id
  route_table_id = aws_route_table.route-table.id
}

resource "aws_route_table_association" "route-table-subnet2-association" {
  subnet_id      = aws_subnet.Public-subnet2.id
  route_table_id = aws_route_table.route-table.id
}
  
resource "aws_network_acl" "Public-NACL" {
  vpc_id = aws_vpc.VPC.id
  subnet_ids = [aws_subnet.Public-subnet1.id, aws_subnet.Public-subnet2.id]

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "Public-NACL"
  }
}

resource "aws_security_group" "load-balancer-sg" {
  name        = "load-balancer-sg"
  description = "Allow inbound traffic from the internet"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "security-grp-rule" {
  name = "allow_ssh_http_https"
  description = "Allow inbound traffic from the internet for private instances"
  vpc_id = aws_vpc.VPC.id

  ingress {
    description = "SSH"
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
      description = "HTTP"
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      security_groups = [aws_security_group.load-balancer-sg.id]
  }

  ingress {
      description = "HTTPS"
      from_port = 443
      to_port = 443
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      security_groups = [aws_security_group.load-balancer-sg.id]
  }

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
}

  tags = {
      Name = "security-grp-rule"
  }
}

resource "aws_instance" "instance-1" {
  ami = "ami-0d09654d0a20d3ae2"
  instance_type = "t2.micro"
  key_name = "main-one"
  subnet_id = aws_subnet.Public-subnet1.id
  vpc_security_group_ids = [aws_security_group.security-grp-rule.id]
  availability_zone = "eu-west-2a"
  tags = {
    Name = "instance-1"
    source = "terraform"
  }
}

resource "aws_instance" "instance-2" {
  ami = "ami-0d09654d0a20d3ae2"
  instance_type = "t2.micro"
  key_name = "main-one"
  subnet_id = aws_subnet.Public-subnet2.id
  vpc_security_group_ids = [aws_security_group.security-grp-rule.id]
  availability_zone = "eu-west-2b"

  tags = {
    Name = "instance-2"
    source = "terraform"
  }
}

resource "aws_instance" "instance-3" {
  ami = "ami-0d09654d0a20d3ae2"
  instance_type = "t2.micro"
  key_name = "main-one"
  subnet_id = aws_subnet.Public-subnet1.id
  vpc_security_group_ids = [aws_security_group.security-grp-rule.id]
  availability_zone = "eu-west-2a"

  tags = {
    Name = "instance-3"
    source = "terraform"
  }
}

resource "local_file" "Ip_address" {
   filename = "/Project/host_inventory"
   content  = <<EOT
${aws_instance.instance-1.public_ip}
${aws_instance.instance-2.public_ip}
${aws_instance.instance-3.public_ip}
  EOT
}

resource "aws_lb" "load-balancer" {
  name               = "load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load-balancer-sg.id]
  subnets            = [aws_subnet.Public-subnet1.id, aws_subnet.Public-subnet2.id]
  enable_deletion_protection = false
  depends_on = [aws_instance.instance-1, aws_instance.instance-2, aws_instance.instance-3]

  tags = {
    Name = "load-balancer"
  }
}

resource "aws_lb_target_group" "target-group" {
  name     = "target-group"
  target_type = "instance"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.VPC.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.load-balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.target-group.arn
    type             = "forward"
  }
}

resource "aws_lb_listener_rule" "listener-rule" {
  listener_arn = aws_lb_listener.listener.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target-group.arn
  }

  condition {
    path_pattern {
      values = ["/"]
    }
  }
}

resource "aws_lb_target_group_attachment" "target-group-attachment1" {
  target_group_arn = aws_lb_target_group.target-group.arn
  target_id        = aws_instance.instance-1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "target-group-attachment2" {
  target_group_arn = aws_lb_target_group.target-group.arn
  target_id        = aws_instance.instance-2.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "target-group-attachment3" {
  target_group_arn = aws_lb_target_group.target-group.arn
  target_id        = aws_instance.instance-3.id
  port             = 80
}

