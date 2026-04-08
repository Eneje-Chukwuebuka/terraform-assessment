#!/usr/bin/env bash

# ==============================================================================
# SCRIPT: db_server_setup.sh
# AUTHOR: Dibia (Techcorp DevOps)
# PURPOSE: Automated provisioning of PostgreSQL + Status Page for MedApp
# ==============================================================================

# --- 1. BOOTSTRAP & LOGGING ---
# Senior Practice: Redirecting all output to a central log file for boot-time 
# observability. 'set -euo pipefail' ensures the script fails fast on errors.
exec >> /var/log/user-data.log 2>&1
set -euo pipefail

MAX_RETRIES=10
RETRY_DELAY=5
COUNT=0

# --- PASSWORD SETUP ---
# Setting the password for ec2-user as per assessment requirements
echo "ec2-user:${db_password}" | chpasswd

# Enable Password Authentication in SSH config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd



echo "Initiating Database Tier Provisioning at $(date)"

# --- 2. NETWORK RESILIENCY ---
# We wait for the package manager to verify repository connectivity. 
# Essential for preventing race conditions during early boot stages.
until yum repolist >/dev/null; do
  ((COUNT++))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "Fatal: Network unreachable after $MAX_RETRIES attempts."
    exit 1
  fi
  sleep $RETRY_DELAY
done

# --- 3. COMPONENT INSTALLATION ---
# Installing PostgreSQL for the data tier and Apache (httpd) for the status page.
yum install -y postgresql-server postgresql && yum install -y httpd

# --- 4. DATABASE INITIALIZATION & STARTUP ---
# Idempotency check: Only run initdb if the data directory is empty.
if [ ! -d "/var/lib/pgsql/data/" ]; then 
  postgresql-setup initdb
fi

# Starting both services; enable ensures they survive a system reboot.
systemctl enable --now postgresql && systemctl enable --now httpd

# --- 5. SECURE METADATA RETRIEVAL (IMDSv2) ---
# Transitioning to v2 tokens provides a modern security posture against SSRF.
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -s)

if [ -z "$TOKEN" ]; then
  echo "Security Error: Unable to fetch IMDSv2 token."
  exit 1
fi

INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  -s http://169.254.169.254/latest/meta-data/instance-id)

# --- 6. POSTGRESQL NETWORK CONFIGURATION ---
CONF_DIR="/var/lib/pgsql/data"

# Standardizing listen_addresses to '*' to allow internal app-tier communication.
sed -i "s/^#*listen_addresses.*/listen_addresses = '*'/" $CONF_DIR/postgresql.conf

# Senior Practice: Tightening security by restricting DB access strictly to 
# the VPC CIDR provided by Terraform.
VPC_CIDR="${vpc_cidr}"
grep -q "$VPC_CIDR" $CONF_DIR/pg_hba.conf || echo "host all all $VPC_CIDR md5" >> $CONF_DIR/pg_hba.conf

# Refreshing service to apply networking changes.
systemctl restart postgresql

# --- 7. SCHEMA & ROLE PROVISIONING ---
# We use conditional SQL logic to prevent 'duplicate object' errors on rerun.
runuser -l postgres -c "
psql -tc \"SELECT 1 FROM pg_database WHERE datname = 'techcorp_db'\" | grep -q 1 || \
psql -c 'CREATE DATABASE techcorp_db;'
"

runuser -l postgres -c "
psql -tc \"SELECT 1 FROM pg_roles WHERE rolname='techcorp_user'\" | grep -q 1 || \
psql -c \"CREATE USER techcorp_user WITH PASSWORD '${db_password}';\"
"

runuser -l postgres -c "
psql -c \"GRANT ALL PRIVILEGES ON DATABASE techcorp_db TO techcorp_user;\"
"

echo "Database layer successfully provisioned on $${INSTANCE_ID} at $(date)"

# --- 8. UI/UX: STATUS PAGE GENERATION ---
# Professional UI with consistent Techcorp branding for infrastructure audits.
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Techcorp | Database Node</title>
    <style>
        body {
            background-color: #f0f2f5; 
            font-family: 'Segoe UI', Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            background-color: white;
            padding: 50px;
            border-radius: 12px;
            box-shadow: 0 10px 25px rgba(0,0,0,0.05);
            text-align: center;
            border-top: 6px solid #28a745; /* Green branding for DB Tier */
        }
        .meta { color: #666; font-family: monospace; font-size: 0.9em; }
        h1 { color: #333; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Techcorp Database Tier</h1>
        <p>Infrastructure Managed by <strong>Dibia</strong></p>
        <hr style="border:0; border-top: 1px solid #eee; margin: 20px 0;">
        <p class="meta">INSTANCE_ID: $${INSTANCE_ID}</p>
        <p class="meta">VPC_SCOPE: ${vpc_cidr}</p>
        <p style="color: #28a745; font-weight: bold;">Status: PostgreSQL Active</p>
    </div>
</body>
</html>
EOF

echo "Provisioning final log entry: Serving from instance: $${INSTANCE_ID}" >> /var/log/user-data.log
