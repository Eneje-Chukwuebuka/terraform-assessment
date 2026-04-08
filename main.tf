# -------------------------------
# VPC (Virtual Private Cloud)
# -------------------------------
# This is the isolated network where all AWS resources will live.
# CIDR defines the total IP range available (e.g. 10.0.0.0/16).
# DNS support is enabled so resources can resolve domain names internally.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -------------------------------
# Internet Gateway (IGW)
# -------------------------------
# Provides a path between the VPC and the internet.
# Only resources in public subnets can use this (via route tables).
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# -------------------------------
# Public Subnets
# -------------------------------
# These subnets are exposed to the internet via the IGW.
# map_public_ip_on_launch ensures instances get public IPs automatically.
# Each subnet is tied to a specific Availability Zone (AZ).
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${each.key}"
  }
}

# -------------------------------
# Private Subnets
# -------------------------------
# These subnets have NO direct internet access.
# Resources here will access the internet only via NAT Gateway (outbound).
resource "aws_subnet" "private" {
  for_each = var.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.project_name}-private-subnet-${each.key}"
  }
}

# -------------------------------
# Elastic IPs (EIP) for NAT Gateways
# -------------------------------
# Each NAT Gateway requires a public static IP.
# One EIP is created per public subnet (per AZ).
resource "aws_eip" "nat" {
  for_each   = var.public_subnets
  depends_on = [aws_internet_gateway.this]
  domain     = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${each.key}"
  }
}

# -------------------------------
# NAT Gateways
# -------------------------------
# Placed inside public subnets.
# Allow private subnets to access the internet (OUTBOUND only).
# One NAT per AZ improves availability and avoids cross-AZ traffic costs.
resource "aws_nat_gateway" "this" {
  for_each = var.public_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = {
    Name = "${var.project_name}-nat-gateway-${each.key}"
  }
}


# Add these two resources to main.tf

resource "aws_eip" "bastion" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-bastion-eip"
  }
}

resource "aws_eip_association" "bastion" {
  instance_id   = aws_instance.bastion.id
  allocation_id = aws_eip.bastion.id
}


# -------------------------------
# Public Route Table
# -------------------------------
# Defines routing rules for public subnets.
# 0.0.0.0/0 → Internet Gateway means full internet access.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

# -------------------------------
# Private Route Tables (per AZ)
# -------------------------------
# Each private subnet gets its own route table.
# Traffic to internet is routed through NAT Gateway in the SAME AZ.
# This avoids cross-AZ traffic and improves resilience.
resource "aws_route_table" "private" {
  for_each = var.private_subnets

  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[each.key].id
  }

  tags = {
    Name = "${var.project_name}-private-route-table-${each.key}"
  }
}

# -------------------------------
# Public Route Table Associations
# -------------------------------
# Associates all public subnets with the public route table.
# This enables internet access via IGW.
resource "aws_route_table_association" "public" {
  for_each = var.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

# -------------------------------
# Private Route Table Associations
# -------------------------------
# Associates each private subnet with its corresponding route table.
# Ensures traffic flows through the correct NAT Gateway.
resource "aws_route_table_association" "private" {
  for_each = var.private_subnets

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}



resource "aws_security_group" "bastion_sg" {
  name        = "${var.project_name}-bastion-sg"
  description = "Allow SSH access to bastion host"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-bastion-sg"
  }
}


resource "aws_security_group" "web_sg" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP/HTTPS access to web servers"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }


  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "${var.project_name}-web-sg"
  }
}

resource "aws_security_group" "db_sg" {
  name        = "${var.project_name}-db-sg"
  description = "Allow PostgreSQL access to database server"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

resource "aws_security_group" "lb" {
  name        = "${var.project_name}-lb-sg"
  description = "the security group for the application load balancer"
  vpc_id      = aws_vpc.this.id



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

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


#:::::::::::::::::::::::::::compute :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::




data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}


resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public[sort(keys(var.public_subnets))[0]].id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
  tags = {
    Name = "${var.project_name}-bastion-host"
  }
}

resource "aws_instance" "web" {
  for_each               = var.private_subnets
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.web_instance_type
  subnet_id              = aws_subnet.private[each.key].id
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  key_name               = var.key_name
  user_data = templatefile("${path.module}/user_data/web_server_setup.sh", {
    vpc_cidr = var.vpc_cidr
    db_password = var.db_password
  })
  tags = {
    Name = "${var.project_name}-web-${each.key}"
  }
}

resource "aws_instance" "db" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.db_instance_type
  subnet_id              = aws_subnet.private[sort(keys(var.private_subnets))[0]].id
  vpc_security_group_ids = [aws_security_group.db_sg.id]
  key_name               = var.key_name
  user_data = templatefile("${path.module}/user_data/db_server_setup.sh", {
    vpc_cidr = var.vpc_cidr
    db_password = var.db_password
  })
  tags = {
    Name = "${var.project_name}-db-server"
  }
}

resource "aws_lb" "this" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = values(aws_subnet.public)[*].id
  tags = {
    Name = "${var.project_name}-alb"
  }
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project_name}-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = {
    Name = "${var.project_name}-web-tg"
  }
}

# Production note: in a real deployment this listener would be replaced
# with a port 443 HTTPS listener using an ACM certificate, and this HTTP
# listener would redirect 301 → HTTPS. Omitted here because this
# assessment uses a raw ALB hostname which cannot have a certificate issued.

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
  tags = {
    Name = "${var.project_name}-web-listener-80"
  }
}


resource "aws_lb_target_group_attachment" "http" {
  for_each         = aws_instance.web
  target_group_arn = aws_lb_target_group.web.arn
  target_id        = each.value.id
  port             = 80
}


