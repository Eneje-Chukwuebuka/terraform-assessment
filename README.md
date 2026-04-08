A production-grade AWS infrastructure built with Terraform.
Deploys a highly available, multi-tier web application across
multiple availability zones with secure network isolation.

_______________________________________________________________________________________________

# Architecture Overview

- **VPC** with public and private subnets across 3 AZs
- **Bastion Host** for secure SSH administrative access
- **2 Web Servers** running Apache behind an Application Load Balancer
- **1 Database Server** running PostgreSQL in an isolated subnet
- **2 NAT Gateways** for high availability outbound internet access
- **Security Groups** to control traffic between resources
- **Route Tables** to control traffic between resources
- **Application Load Balancer** to distribute traffic to web servers
- **Target Groups** to route traffic to web servers
- **Listener** to listen for incoming traffic

## Prerequisites

Before deploying, ensure you have the following installed and configured:

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.0.4
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- An AWS account with sufficient permissions to create VPC, EC2, and ELB resources
- An existing AWS Key Pair in your target region

To configure AWS CLI:
```bash
aws configure
```

To verify your identity:
```bash
aws sts get-caller-identity
```

_______________________________________________________________________________________________

## File Structure
```
terraform-assessment/
├── main.tf                    # All resource definitions
├── variables.tf               # Variable declarations
├── outputs.tf                 # Output definitions
├── locals.tf                  # Local value computations
├── provider.tf                # AWS provider configuration
├── terraform.tfvars.example   # Example variable values
├── user_data/
│   ├── webserver1_setup.sh    # Apache install script for web server 1
│   ├── webserver2_setup.sh    # Apache install script for web server 2
│   └── dbserver_setup.sh      # PostgreSQL install script
├── evidence/                  # Deployment screenshots
└── README.md                  # This file


### Deployment Steps

**1. Clone the repository**
```bash
git clone https://github.com/YOUR_USERNAME/month-one-assessment
cd month-one-assessment
```

**2. Copy the example variables file**
```bash
cp terraform.tfvars.example terraform.tfvars
```

**3. Edit `terraform.tfvars` with your values**
```bash
code terraform.tfvars
```

Fill in:
- `my_ip` — your public IP address (run `curl checkip.amazonaws.com`)
- `key_name` — your AWS key pair name

**4. Initialise Terraform**
```bash
terraform init
```

**5. Review the deployment plan**
```bash
terraform plan -out=tfplan
```

**6. Apply the configuration**
```bash
terraform apply tfplan
```

**7. Access the application**

After apply completes, Terraform will output:
- `lb_main_dns_name` — paste into browser to access the app
- `bastion_eip_public_ip` — use this IP to SSH into the bastion

_____________________________________________________________________________________________

## SSH Access

**Connect to Bastion Host:**
```bash
ssh -i techcorp-key.pem ec2-user@
```

**Connect to Web Servers from Bastion:**
```bash
ssh ec2-user@
```

**Connect to Database Server from Bastion:**
```bash
ssh ec2-user@
```

**Connect to PostgreSQL:**
```bash
psql -U postgres
```

_____________________________________________________________________________________________

## Cleanup

To destroy all resources and avoid AWS charges:
```bash
terraform destroy
```

Type `yes` when prompted. This permanently deletes all resources
created by this configuration.

> ⚠️ There is no undo. Ensure you have taken all required screenshots
> before destroying.

_____________________________________________________________________________________________

## Author

- **Name:** Dibia 
- **Role:** Junior Cloud Engineer
- **Project:** TechCorp Infrastructure stimualation
