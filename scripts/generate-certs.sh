#!/bin/bash
set -e

# Certificate generation script for EMQX MQTT broker
# This script generates:
# - CA (Certificate Authority)
# - Server certificate for EMQX
# - Client certificates for device authentication

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/../certs"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Generating TLS certificates for EMQX MQTT broker...${NC}"

# Create certs directory
mkdir -p "${CERTS_DIR}"
cd "${CERTS_DIR}"

# Configuration
CA_KEY_SIZE=4096
SERVER_KEY_SIZE=2048
CLIENT_KEY_SIZE=2048
VALIDITY_DAYS=365

# Step 1: Generate CA private key
echo -e "${YELLOW}[1/7] Generating CA private key...${NC}"
openssl genrsa -out ca.key ${CA_KEY_SIZE}
chmod 600 ca.key

# Step 2: Generate CA certificate
echo -e "${YELLOW}[2/7] Generating CA certificate...${NC}"
openssl req -new -x509 -days ${VALIDITY_DAYS} -key ca.key -out ca.crt \
  -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=EMQX CA"

# Step 3: Generate server private key
echo -e "${YELLOW}[3/7] Generating server private key...${NC}"
openssl genrsa -out emqx-server.key ${SERVER_KEY_SIZE}
chmod 600 emqx-server.key

# Step 4: Generate server certificate signing request
echo -e "${YELLOW}[4/7] Generating server certificate signing request...${NC}"
openssl req -new -key emqx-server.key -out emqx-server.csr \
  -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=emqx-server"

# Step 5: Generate server certificate (signed by CA)
echo -e "${YELLOW}[5/7] Signing server certificate with CA...${NC}"
openssl x509 -req -days ${VALIDITY_DAYS} -in emqx-server.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out emqx-server.crt \
  -extensions v3_req -extfile <(
    echo "[v3_req]"
    echo "subjectAltName = @alt_names"
    echo "[alt_names]"
    echo "DNS.1 = localhost"
    echo "DNS.2 = *.emqx.internal"
    echo "DNS.3 = emqx-server"
    echo "IP.1 = 127.0.0.1"
  )

# Clean up CSR
rm emqx-server.csr

# Step 6: Generate client certificate (example)
echo -e "${YELLOW}[6/7] Generating example client certificate...${NC}"
CLIENT_NAME="device-001"
openssl genrsa -out ${CLIENT_NAME}.key ${CLIENT_KEY_SIZE}
chmod 600 ${CLIENT_NAME}.key
openssl req -new -key ${CLIENT_NAME}.key -out ${CLIENT_NAME}.csr \
  -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=${CLIENT_NAME}"

openssl x509 -req -days ${VALIDITY_DAYS} -in ${CLIENT_NAME}.csr -CA ca.crt -CAkey ca.key \
  -CAcreateserial -out ${CLIENT_NAME}.crt

rm ${CLIENT_NAME}.csr

# Create PKCS12 bundle for client (password: changeit)
echo -e "${YELLOW}[7/7] Creating client PKCS12 bundle...${NC}"
openssl pkcs12 -export -out ${CLIENT_NAME}.p12 -inkey ${CLIENT_NAME}.key \
  -in ${CLIENT_NAME}.crt -certfile ca.crt -passout pass:changeit

# Generate additional client certificates if needed
generate_client_cert() {
  local client_name=$1
  echo -e "${YELLOW}Generating client certificate: ${client_name}...${NC}"
  
  openssl genrsa -out ${client_name}.key ${CLIENT_KEY_SIZE}
  chmod 600 ${client_name}.key
  openssl req -new -key ${client_name}.key -out ${client_name}.csr \
    -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=${client_name}"
  
  openssl x509 -req -days ${VALIDITY_DAYS} -in ${client_name}.csr -CA ca.crt -CAkey ca.key \
    -CAcreateserial -out ${client_name}.crt
  
  rm ${client_name}.csr
  
  openssl pkcs12 -export -out ${client_name}.p12 -inkey ${client_name}.key \
    -in ${client_name}.crt -certfile ca.crt -passout pass:changeit
  
  echo -e "${GREEN}Client certificate ${client_name} created successfully${NC}"
}

# Generate additional client certificates
if [ "$#" -gt 0 ]; then
  for client_name in "$@"; do
    generate_client_cert "$client_name"
  done
else
  # Generate a few example client certificates
  generate_client_cert "device-002"
  generate_client_cert "device-003"
fi

# Copy CA cert with different name for EMQX
cp ca.crt ca.pem

# Create archive for upload to GCS
echo -e "${YELLOW}Creating certificate archive...${NC}"
tar -czf emqx-server-certs.tar.gz emqx-server.key emqx-server.crt ca.crt ca.pem
tar -czf all-certs.tar.gz *.key *.crt *.pem *.p12 2>/dev/null || true

echo -e "${GREEN}✓ Certificate generation completed!${NC}"
echo ""
echo -e "${YELLOW}Generated files:${NC}"
echo "  - ca.crt / ca.pem: Certificate Authority (needed by server and clients)"
echo "  - emqx-server.key: Server private key"
echo "  - emqx-server.crt: Server certificate"
echo "  - device-*.key/crt: Client certificates"
echo "  - device-*.p12: PKCS12 bundles for clients"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Upload server certificates to GCS bucket:"
echo "   gsutil cp emqx-server.* ca.pem gs://<bucket-name>/"
echo ""
echo "2. Distribute client certificates securely to your devices"
echo ""
echo -e "${YELLOW}Certificate location: ${CERTS_DIR}${NC}"

