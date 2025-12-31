# Certificate generation script for EMQX MQTT broker (PowerShell)
# This script generates:
# - CA (Certificate Authority)
# - Server certificate for EMQX
# - Client certificates for device authentication

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertsDir = Join-Path $ScriptDir "..\certs"

Write-Host "Generating TLS certificates for EMQX MQTT broker..." -ForegroundColor Green

# Create certs directory
if (-not (Test-Path $CertsDir)) {
    New-Item -ItemType Directory -Path $CertsDir | Out-Null
}
Set-Location $CertsDir

# Configuration
$CA_KEY_SIZE = 4096
$SERVER_KEY_SIZE = 2048
$CLIENT_KEY_SIZE = 2048
$VALIDITY_DAYS = 365

# Check if OpenSSL is available
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    Write-Host "Error: OpenSSL is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install OpenSSL: https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor Yellow
    exit 1
}

# Step 1: Generate CA private key
Write-Host "[1/7] Generating CA private key..." -ForegroundColor Yellow
openssl genrsa -out ca.key $CA_KEY_SIZE

# Step 2: Generate CA certificate
Write-Host "[2/7] Generating CA certificate..." -ForegroundColor Yellow
openssl req -new -x509 -days $VALIDITY_DAYS -key ca.key -out ca.crt `
    -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=EMQX CA"

# Step 3: Generate server private key
Write-Host "[3/7] Generating server private key..." -ForegroundColor Yellow
openssl genrsa -out emqx-server.key $SERVER_KEY_SIZE

# Step 4: Generate server certificate signing request
Write-Host "[4/7] Generating server certificate signing request..." -ForegroundColor Yellow
openssl req -new -key emqx-server.key -out emqx-server.csr `
    -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=emqx-server"

# Step 5: Create extensions file for server certificate
$extFile = Join-Path $CertsDir "server-ext.conf"
@"
[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = localhost
DNS.2 = *.emqx.internal
DNS.3 = emqx-server
IP.1 = 127.0.0.1
"@ | Out-File -FilePath $extFile -Encoding ASCII

# Generate server certificate (signed by CA)
Write-Host "[5/7] Signing server certificate with CA..." -ForegroundColor Yellow
openssl x509 -req -days $VALIDITY_DAYS -in emqx-server.csr -CA ca.crt -CAkey ca.key `
    -CAcreateserial -out emqx-server.crt -extensions v3_req -extfile $extFile

# Clean up
Remove-Item emqx-server.csr
Remove-Item $extFile

# Step 6: Generate client certificate (example)
Write-Host "[6/7] Generating example client certificate..." -ForegroundColor Yellow
$CLIENT_NAME = "device-001"
openssl genrsa -out "$CLIENT_NAME.key" $CLIENT_KEY_SIZE
openssl req -new -key "$CLIENT_NAME.key" -out "$CLIENT_NAME.csr" `
    -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=$CLIENT_NAME"

openssl x509 -req -days $VALIDITY_DAYS -in "$CLIENT_NAME.csr" -CA ca.crt -CAkey ca.key `
    -CAcreateserial -out "$CLIENT_NAME.crt"

Remove-Item "$CLIENT_NAME.csr"

# Step 7: Create PKCS12 bundle for client (password: changeit)
Write-Host "[7/7] Creating client PKCS12 bundle..." -ForegroundColor Yellow
$password = "changeit"
echo $password | openssl pkcs12 -export -out "$CLIENT_NAME.p12" -inkey "$CLIENT_NAME.key" `
    -in "$CLIENT_NAME.crt" -certfile ca.crt -passout stdin

# Generate additional client certificates if provided as arguments
function Generate-ClientCert {
    param($clientName)
    
    Write-Host "Generating client certificate: $clientName..." -ForegroundColor Yellow
    
    openssl genrsa -out "$clientName.key" $CLIENT_KEY_SIZE
    openssl req -new -key "$clientName.key" -out "$clientName.csr" `
        -subj "/C=PL/ST=State/L=City/O=IoT Organization/CN=$clientName"
    
    openssl x509 -req -days $VALIDITY_DAYS -in "$clientName.csr" -CA ca.crt -CAkey ca.key `
        -CAcreateserial -out "$clientName.crt"
    
    Remove-Item "$clientName.csr"
    
    echo $password | openssl pkcs12 -export -out "$clientName.p12" -inkey "$clientName.key" `
        -in "$clientName.crt" -certfile ca.crt -passout stdin
    
    Write-Host "Client certificate $clientName created successfully" -ForegroundColor Green
}

# Generate additional client certificates
if ($args.Count -gt 0) {
    foreach ($clientName in $args) {
        Generate-ClientCert $clientName
    }
} else {
    # Generate a few example client certificates
    Generate-ClientCert "device-002"
    Generate-ClientCert "device-003"
}

# Copy CA cert with different name for EMQX
Copy-Item ca.crt ca.pem

# Create archive for upload to GCS (requires tar, available in Windows 10+)
Write-Host "Creating certificate archive..." -ForegroundColor Yellow
if (Get-Command tar -ErrorAction SilentlyContinue) {
    tar -czf emqx-server-certs.tar.gz emqx-server.key emqx-server.crt ca.crt ca.pem
    tar -czf all-certs.tar.gz *.key *.crt *.pem *.p12 2>$null
} else {
    Write-Host "Note: tar not available, skipping archive creation" -ForegroundColor Yellow
}

Write-Host "`nCertificate generation completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Generated files:" -ForegroundColor Yellow
Write-Host "  - ca.crt / ca.pem: Certificate Authority (needed by server and clients)"
Write-Host "  - emqx-server.key: Server private key"
Write-Host "  - emqx-server.crt: Server certificate"
Write-Host "  - device-*.key/crt: Client certificates"
Write-Host "  - device-*.p12: PKCS12 bundles for clients"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Upload server certificates to GCS bucket:"
Write-Host "   gsutil cp emqx-server.* ca.pem gs://<bucket-name>/"
Write-Host ""
Write-Host "2. Distribute client certificates securely to your devices"
Write-Host ""
Write-Host "Certificate location: $CertsDir" -ForegroundColor Yellow

