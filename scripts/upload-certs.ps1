# Script to upload certificates to GCS bucket (PowerShell)
# Usage: .\upload-certs.ps1 <bucket-name>

param(
    [Parameter(Mandatory=$true)]
    [string]$BucketName
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CertsDir = Join-Path $ScriptDir "..\certs"

if (-not (Test-Path $CertsDir)) {
    Write-Host "Error: Certificates directory not found: $CertsDir" -ForegroundColor Red
    Write-Host "Please run generate-certs.ps1 first" -ForegroundColor Yellow
    exit 1
}

$gsutil = Get-Command gsutil -ErrorAction SilentlyContinue
if (-not $gsutil) {
    Write-Host "Error: gsutil is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Google Cloud SDK: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

Write-Host "Uploading certificates to gs://$BucketName/..." -ForegroundColor Green

# Upload server certificates
gsutil cp "$CertsDir\emqx-server.key" "gs://$BucketName/"
gsutil cp "$CertsDir\emqx-server.crt" "gs://$BucketName/"
gsutil cp "$CertsDir\ca.crt" "gs://$BucketName/ca.pem"

Write-Host "`nCertificates uploaded successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Don't forget to restart EMQX instances:" -ForegroundColor Yellow
Write-Host "  gcloud compute instances list --filter=`"name~emqx`""
Write-Host "  gcloud compute instances reset <instance-name> --zone=<zone>"

