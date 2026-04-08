#!/bin/bash

# ==============================================================================
# SCRIPT: web_server_setup.sh
# AUTHOR: Dibia (Techcorp DevOps)
# PURPOSE: Automated provisioning of styled Web Nodes for MedApp
# ==============================================================================

# --- 1. BOOTSTRAP & ERROR HANDLING ---
# We use 'set -euo pipefail' to ensure the script stops immediately on any error.
# This prevents "zombie" instances that look 'Running' but are actually broken.
set -euo pipefail
exec >> /var/log/user-data.log 2>&1

# --- 2. DYNAMIC VARIABLE VALIDATION ---
# Terraform injects these via templatefile. We validate them here to catch 
# configuration gaps before the application starts.
if [ -z "${vpc_cidr}" ]; then
  echo "Critical Error: vpc_cidr must be supplied by Terraform"
  exit 1
fi

# --- 3. NETWORK RESILIENCY LOOP ---
# Cloud instances sometimes boot faster than the network routing tables update.
# This loop ensures we don't fail the 'yum install' due to temporary 503 errors.
MAX_RETRIES=10
COUNT=0
echo "Checking network connectivity..."
until yum repolist >/dev/null; do
  ((COUNT++))
  if [ $COUNT -ge $MAX_RETRIES ]; then
    echo "Timeout: Network unavailable. Manual intervention required."
    exit 1
  fi
  sleep 5
done

# --- 4. WEBSERVER INSTALLATION & OPTIMIZATION ---
# Using 'httpd' (Apache). We enable the service to ensure that if the instance 
# reboots (due to AWS maintenance), the MedApp website comes back up automatically.
yum install -y httpd
systemctl enable --now httpd

# --- 5. IDENTITY DISCOVERY (IMDSv2) ---
# We use the Session Token approach (Version 2) to protect against SSRF attacks.
# This is a security-first requirement for all Techcorp infrastructure.
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" -s)

if [ -z "$TOKEN" ]; then
  echo "Failed to retrieve IMDSv2 token"
  exit 1
fi

INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" \
  -s http://169.254.169.254/latest/meta-data/instance-id)

# Log the instance ID to our background log file for auditability
echo "Serving from instance: $${INSTANCE_ID}" >> /var/log/user-data.log

# --- 6. DYNAMIC UI GENERATION ---
# We generate the index.html on-the-fly. This allows us to display unique 
# metadata per instance, which is vital for verifying Load Balancer distribution.
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Techcorp | Web Node</title>
    <style>
        /* Professional UI: Centered layout with consistent branding */
        body {
            background-color: #f0f2f5; 
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .card {
            background-color: #ffffff;
            padding: 3rem;
            border-radius: 12px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.08);
            text-align: center;
            border-top: 6px solid #0056b3; /* Techcorp Corporate Blue */
            max-width: 500px;
        }
        h1 { color: #1a1a1b; margin-bottom: 0.5rem; }
        p { color: #4a4a4a; line-height: 1.6; }
        .badge {
            background: #e9ecef;
            padding: 4px 10px;
            border-radius: 4px;
            font-family: monospace;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>MedApp System Online</h1>
        <p>Infrastructure Managed by <strong>Dibia</strong></p>
        <hr style="border: 0; border-top: 1px solid #eee; margin: 1.5rem 0;">
        <p><strong>Instance ID:</strong> <span class="badge">$${INSTANCE_ID}</span></p>
        <p><strong>Network Scope:</strong> <span class="badge">${vpc_cidr}</span></p>
        <p style="font-size: 0.8rem; color: #888;">Provisioned: $(date "+%Y-%m-%d %H:%M:%S UTC")</p>
    </div>
</body>
</html>
EOF

# --- 7. FINAL TELEMETRY ---
# Final log entry to confirm successful execution of the entire sequence.
echo "Provisioning sequence completed successfully at $(date)"
