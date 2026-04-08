# variables.tf
# All input variables for the TechCorp infrastructure.
# Rule: if a value changes between environments (dev/staging/prod) or between
# engineers, it belongs here — never hardcoded in main.tf.

# -----------------------------------------------------------------------------
# GLOBAL
# -----------------------------------------------------------------------------

variable "region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
  # Changing this one value moves your entire infrastructure to a different
  # region. This is the power of variables — no grep-and-replace needed.
}

variable "project_name" {
  description = "Project name used as a prefix on all resource Name tags"
  type        = string
  default     = "techcorp"
  # Every resource will be named "${var.project_name}-vpc",
  # "${var.project_name}-bastion" etc. Consistent naming is how you stay
  # sane when you have 50 resources in the AWS console.
}

# -----------------------------------------------------------------------------
# NETWORKING
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
  # /16 gives you 65,536 IP addresses — plenty of room to carve subnets.
  # The 10.x.x.x range is RFC 1918 private space — it is never routable
  # on the public internet, which is exactly what you want for a VPC.
}

variable "public_subnets" {
  description = "Map of availability zone to CIDR block for public subnets"
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }
  # Using a map instead of numbered variables (subnet_cidr_1, subnet_cidr_2)
  # means each subnet is identified by its AZ — self-documenting and stable.
  #
  # With for_each, Terraform keys resources by map key ("us-east-1a") rather
  # than by index number. This matters: if you remove a subnet, index-based
  # resources renumber and Terraform tries to destroy/recreate everything.
  # Key-based resources are unaffected by additions or removals elsewhere.
  #
  # /24 = 256 addresses per subnet (AWS reserves 5, so 251 usable).
  # Public subnets host resources that need a direct internet route:
  # the ALB, the bastion host, and the NAT Gateways.
}

variable "private_subnets" {
  description = "Map of availability zone to CIDR block for private subnets"
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.3.0/24"
    "us-east-1b" = "10.0.4.0/24"
  }
  # Private subnets have NO direct route to the internet.
  # Instances here (web servers, DB) can reach the internet only via the
  # NAT Gateway — outbound only. No inbound connections from the internet
  # are possible. Think of it as the hospital ICU: staff can call out,
  # but no one walks in off the street.
}

# -----------------------------------------------------------------------------
# COMPUTE
# -----------------------------------------------------------------------------

variable "bastion_instance_type" {
  description = "EC2 instance type for the bastion host"
  type        = string
  default     = "t3.micro"
  # The bastion does almost nothing — it just forwards SSH sessions.
  # t3.micro is more than enough. Spending money on a large bastion
  # is a common waste you will see in less mature setups.
}

variable "web_instance_type" {
  description = "EC2 instance type for web servers"
  type        = string
  default     = "t3.micro"
  # Kept separate from bastion_instance_type deliberately.
  # In production, web servers will need upscaling independently of the
  # bastion. If you merged these into one variable, you couldn't change
  # one without affecting the other.
}

variable "db_instance_type" {
  description = "EC2 instance type for the database server"
  type        = string
  default     = "t3.small"
  # DB gets t3.small (not micro) because PostgreSQL needs more memory
  # to handle connections and query caching effectively.
  # DB servers are almost always the first bottleneck — give them room.
}

# -----------------------------------------------------------------------------
# ACCESS & SECURITY
# -----------------------------------------------------------------------------


variable "my_ip" {
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32) — restricts SSH access to the bastion"
  type        = string
  # No default — this MUST be supplied explicitly in terraform.tfvars.
  # Terraform will error at plan time if it is missing, which is correct
  # behaviour: you never want to accidentally deploy a bastion open to
  # the whole internet (0.0.0.0/0) because a variable was forgotten.
  #
  # /32 means exactly one IP address — yours. This is the tightest
  # possible security group rule for SSH. Find your IP by running:
  #   curl ifconfig.me
  # then set: my_ip = "YOUR_IP/32" in terraform.tfvars
}



variable "db_password" {
  description = "Password for the database user"
  type        = string
  sensitive   = true
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access (leave empty if using password auth)"
  type        = string
  default     = "techcorp-key"
  # Empty string default means: key pair is optional.
  # The brief uses username/password as the primary method.
  # If you hardcode a specific key name here (e.g. "techcorp-key"), the
  # config breaks for every other engineer whose AWS account doesn't have
  # that exact key — a very common beginner mistake.
}

variable "key_path" {
  description = "Path to the private key file"
  type        = string
  default     = "techcorp-key.pem"
}
