#!/usr/bin/env bash
# GCP Terraform Project Destroyer
# Safely destroys Terraform-managed infrastructure with confirmation.
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}GCP Terraform Project Destroyer${NC}\n"

# Check prerequisites
command -v terraform &>/dev/null || { echo -e "${RED}Error: Terraform not installed${NC}"; exit 1; }

# Discover Terraform projects
echo -e "${BLUE}Available Terraform projects:${NC}"
PROJECTS=()
for dir in "$SCRIPT_DIR"/*/; do
  if [ -f "$dir/main.tf" ]; then
    PROJECT_NAME=$(basename "$dir")
    PROJECTS+=("$PROJECT_NAME")
    echo "  - $PROJECT_NAME"
  fi
done

if [ ${#PROJECTS[@]} -eq 0 ]; then
  echo -e "${YELLOW}No Terraform projects found${NC}"
  exit 1
fi

echo ""
read -p "Project to destroy: " PROJECT

# Validate selection
FOUND=false
for p in "${PROJECTS[@]}"; do
  [ "$p" = "$PROJECT" ] && FOUND=true
done
$FOUND || { echo -e "${RED}Invalid project: ${PROJECT}${NC}"; exit 1; }

PROJECT_DIR="$SCRIPT_DIR/$PROJECT"
cd "$PROJECT_DIR"

# Check for state
if [ ! -f "terraform.tfstate" ] && [ ! -d ".terraform" ]; then
  echo -e "${YELLOW}No Terraform state found in ${PROJECT}. Nothing to destroy.${NC}"
  exit 0
fi

# Show what will be destroyed
echo -e "\n${BLUE}Resources managed by Terraform:${NC}"
terraform state list 2>/dev/null || echo "  (unable to list state)"

echo -e "\n${YELLOW}WARNING: This will permanently destroy all resources in '${PROJECT}'.${NC}"
read -p "Type the project name to confirm: " CONFIRM
[ "$CONFIRM" != "$PROJECT" ] && { echo -e "${RED}Confirmation failed. Aborting.${NC}"; exit 1; }

echo -e "\n${BLUE}Destroying ${PROJECT}...${NC}"
terraform destroy -auto-approve

echo -e "\n${GREEN}Project ${PROJECT} destroyed successfully.${NC}"
