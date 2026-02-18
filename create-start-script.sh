#!/usr/bin/env bash
# GCP Compute Engine Start Script Generator
# Creates a one-command launcher to start and SSH into a Compute Engine instance.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"

echo -e "${BLUE}GCP Compute Engine Start Script Generator${NC}\n"

# Check prerequisites
command -v gcloud &>/dev/null || { echo -e "${RED}Error: gcloud CLI not installed${NC}"; exit 1; }
gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null || { echo -e "${RED}Error: Not authenticated. Run: gcloud auth login${NC}"; exit 1; }

# Project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
read -p "GCP Project ID [${CURRENT_PROJECT}]: " PROJECT_ID
PROJECT_ID="${PROJECT_ID:-$CURRENT_PROJECT}"
[ -z "$PROJECT_ID" ] && { echo -e "${RED}No project ID provided${NC}"; exit 1; }

# List instances
echo -e "\n${BLUE}Instances in ${PROJECT_ID}:${NC}"
gcloud compute instances list --project="$PROJECT_ID" --format="table(name,zone,machineType.basename(),status)" 2>/dev/null

echo ""
read -p "Instance name: " INSTANCE_NAME
[ -z "$INSTANCE_NAME" ] && { echo -e "${RED}No instance name provided${NC}"; exit 1; }

read -p "Zone [asia-southeast1-b]: " ZONE
ZONE="${ZONE:-asia-southeast1-b}"

read -p "SSH username [$(whoami)]: " SSH_USER
SSH_USER="${SSH_USER:-$(whoami)}"

SCRIPT_NAME="start-gcp-${INSTANCE_NAME}"
SCRIPT_NAME=$(echo "$SCRIPT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')

# Generate the start script
SCRIPT_PATH="$LOCAL_BIN/$SCRIPT_NAME"
cat > "$SCRIPT_PATH" << STARTSCRIPT
#!/usr/bin/env bash
# Start and connect to GCP instance: ${INSTANCE_NAME}
set -euo pipefail

INSTANCE_NAME="${INSTANCE_NAME}"
ZONE="${ZONE}"
PROJECT_ID="${PROJECT_ID}"
SSH_USER="${SSH_USER}"
SSH_CONFIG="\${HOME}/.ssh/config"
SSH_HOST_ALIAS="gcp-${INSTANCE_NAME}"

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "\$1" "\$2" -u low -t 3000
  fi
}

echo "Checking instance state..."
STATE=\$(gcloud compute instances describe "\$INSTANCE_NAME" --zone="\$ZONE" --project="\$PROJECT_ID" \
  --format="value(status)" 2>/dev/null)

if [ "\$STATE" = "TERMINATED" ]; then
  echo "Starting instance \$INSTANCE_NAME..."
  notify "GCP Dev Box" "Waking up instance..."
  gcloud compute instances start "\$INSTANCE_NAME" --zone="\$ZONE" --project="\$PROJECT_ID"
elif [ "\$STATE" = "RUNNING" ]; then
  echo "Instance already running."
else
  echo "Instance is in state: \$STATE"
  exit 1
fi

IP=\$(gcloud compute instances describe "\$INSTANCE_NAME" --zone="\$ZONE" --project="\$PROJECT_ID" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo "Instance is up at: \$IP"

mkdir -p "\$(dirname "\$SSH_CONFIG")"
touch "\$SSH_CONFIG"
if grep -q "# GCP_DEV_BOX_START \${SSH_HOST_ALIAS}" "\$SSH_CONFIG"; then
  sed -i "/# GCP_DEV_BOX_START \${SSH_HOST_ALIAS}/,/# GCP_DEV_BOX_END \${SSH_HOST_ALIAS}/ s/HostName .*/HostName \$IP/" "\$SSH_CONFIG"
else
  cat >> "\$SSH_CONFIG" <<EOF
# GCP_DEV_BOX_START \${SSH_HOST_ALIAS}
Host \${SSH_HOST_ALIAS}
  HostName \$IP
  User \$SSH_USER
# GCP_DEV_BOX_END \${SSH_HOST_ALIAS}
EOF
fi
echo "SSH config updated for host alias: \$SSH_HOST_ALIAS"
notify "GCP Dev Box Ready" "Instance is UP at \$IP. SSH config updated."

echo "Connecting via SSH..."
gcloud compute ssh "\$INSTANCE_NAME" --zone="\$ZONE" --project="\$PROJECT_ID"
STARTSCRIPT

chmod +x "$SCRIPT_PATH"

echo -e "\n${GREEN}Start script created: ${SCRIPT_PATH}${NC}"
echo -e "Run it with: ${BLUE}${SCRIPT_NAME}${NC}"
echo -e "\nMake sure ${LOCAL_BIN} is in your PATH:"
echo -e '  export PATH="$HOME/.local/bin:$PATH"'
