#!/usr/bin/env bash
# Run locally (after gcloud auth login) to create GCP project and VM.
# Usage: bash scripts/provision-gcp.sh
set -euo pipefail

PROJECT_ID="nightscout-sugarfield"
ZONE="us-central1-a"
VM_NAME="nightscout-vm"
MACHINE="e2-micro"
IMAGE_FAMILY="ubuntu-2204-lts"
IMAGE_PROJECT="ubuntu-os-cloud"
DISK_SIZE="30GB"
DISK_TYPE="pd-standard"
ACCOUNT="mill4433.purdue@gmail.com"

echo "=== Authenticating with GCP ==="
gcloud auth login --account="$ACCOUNT"

echo "=== Creating project $PROJECT_ID ==="
gcloud projects create "$PROJECT_ID" --name="Nightscout Sugarfield" 2>/dev/null || \
  echo "Project already exists, continuing..."

gcloud config set project "$PROJECT_ID"

echo "=== Linking billing account ==="
BILLING=$(gcloud billing accounts list --format="value(name)" | head -1)
if [ -z "$BILLING" ]; then
  echo "ERROR: No billing account found for $ACCOUNT."
  echo "Visit https://console.cloud.google.com/billing to set one up, then re-run."
  exit 1
fi
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING"

echo "=== Enabling Compute Engine API ==="
gcloud services enable compute.googleapis.com --project="$PROJECT_ID"
echo "Waiting for API to propagate..."
sleep 15

echo "=== Creating VM ==="
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --machine-type="$MACHINE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --boot-disk-size="$DISK_SIZE" \
  --boot-disk-type="$DISK_TYPE" \
  --tags="nightscout-server" \
  --metadata="enable-oslogin=false"

echo "=== Firewall: allow HTTP + HTTPS ==="
gcloud compute firewall-rules create allow-nightscout-web \
  --project="$PROJECT_ID" \
  --direction=INGRESS \
  --action=ALLOW \
  --rules=tcp:80,tcp:443 \
  --source-ranges=0.0.0.0/0 \
  --target-tags=nightscout-server \
  2>/dev/null || echo "Firewall rule already exists."

echo ""
echo "=== VM Created! ==="
VM_IP=$(gcloud compute instances describe "$VM_NAME" \
  --project="$PROJECT_ID" \
  --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo "External IP: $VM_IP"
echo ""
echo "NEXT STEPS:"
echo "1. Add a DNS A record: ns-sf.joshnliz.com → $VM_IP  (in Cloudflare, set to DNS only / grey cloud)"
echo "2. Wait ~1 minute for DNS to propagate"
echo "3. SSH into VM: gcloud compute ssh $VM_NAME --zone=$ZONE --project=$PROJECT_ID"
echo "4. Run setup script: bash /tmp/setup-vm.sh"
echo ""
echo "To copy setup script to VM:"
echo "  gcloud compute scp scripts/setup-vm.sh $VM_NAME:/tmp/setup-vm.sh --zone=$ZONE --project=$PROJECT_ID"
