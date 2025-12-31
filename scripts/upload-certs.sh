#!/bin/bash
set -e

# Script to upload certificates to GCS bucket
# Usage: ./upload-certs.sh [bucket-name]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

if [ -z "$1" ]; then
    echo "Usage: $0 <bucket-name>"
    echo "Example: $0 emqx-certificates-bucket-iot-proj-482921"
    exit 1
fi

BUCKET_NAME=$1

if [ ! -d "${CERTS_DIR}" ]; then
    echo "Error: Certificates directory not found: ${CERTS_DIR}"
    echo "Please run generate-certs.sh first"
    exit 1
fi

echo "Uploading certificates to gs://${BUCKET_NAME}/..."

# Upload server certificates
gsutil cp "${CERTS_DIR}/emqx-server.key" "gs://${BUCKET_NAME}/"
gsutil cp "${CERTS_DIR}/emqx-server.crt" "gs://${BUCKET_NAME}/"
gsutil cp "${CERTS_DIR}/ca.crt" "gs://${BUCKET_NAME}/ca.pem"

echo "✓ Certificates uploaded successfully!"
echo ""
echo "Don't forget to restart EMQX instances:"
echo "  gcloud compute instances list --filter='name~emqx'"
echo "  gcloud compute instances reset <instance-name> --zone=<zone>"

