# EMQX MQTT Broker na Google Cloud Platform

Projekt Terraform do wdrożenia brokera EMQX na GCP z zabezpieczeniem TLS client certificate authentication.

## 📋 Wymagania

- Konto Google Cloud Platform
- Projekt GCP utworzony (ID projektu: `iot-proj-482921` lub własny)
- `gcloud` CLI zainstalowane i skonfigurowane
- `terraform` >= 1.0
- `openssl` (do generowania certyfikatów)
- Node.js i npm (opcjonalnie, do testowania klientów)

## 🏗️ Architektura

- **EMQX Broker**: 1 instancja VM w Managed Instance Group (można zwiększyć przez `emqx_instance_count`)
- **Load Balancer**: TCP Load Balancer dla portów prod (8883) i dev (8884)
- **Bezpieczeństwo**: TLS z client certificate authentication
- **Porty**:
  - 8883: MQTTS Production
  - 8884: MQTTS Development
  - 18083: Dashboard HTTP
  - 8083: WebSocket (bez TLS)
  - 8084: WebSocket Secure (WSS)

## 🚀 Instalacja krok po kroku

### Krok 1: Przygotowanie projektu GCP

```bash
# Zaloguj się do GCP
gcloud auth login

# Ustaw projekt (zastąp własnym ID projektu)
gcloud config set project iot-proj-482921

# Włącz wymagane API
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
```

### Krok 2: Konfiguracja Terraform

```bash
# Skonfiguruj zmienne (opcjonalnie - wszystkie mają wartości domyślne)
# Zmienne można nadpisać tworząc terraform.tfvars lub używając -var
```

**Dostępne zmienne** (definiowane w `variables.tf`):
- `project_id`: ID projektu GCP (domyślnie: "iot-proj-482921")
- `region`: Region GCP (domyślnie: "europe-west1")
- `zone`: Strefa GCP (domyślnie: "europe-west1-b")
- `emqx_instance_count`: Liczba instancji EMQX (domyślnie: 1)
- `emqx_machine_type`: Typ maszyny (domyślnie: "e2-medium")
- `emqx_version`: Wersja EMQX (domyślnie: "5.3.2")

### Krok 3: Generowanie certyfikatów TLS

#### Windows (PowerShell):

```powershell
cd scripts
.\generate-certs.ps1
```

#### Linux/Mac:

```bash
cd scripts
chmod +x generate-certs.sh
./generate-certs.sh
```

**Wygenerowane certyfikaty** (w folderze `certs/`):
- `ca.crt`, `ca.key` - Certificate Authority
- `emqx-server.crt`, `emqx-server.key` - Certyfikat serwera
- `device-001.crt`, `device-001.key` - Certyfikat klienta (przykładowy)

### Krok 4: Upload certyfikatów do Google Cloud Storage

Certyfikaty serwera muszą być dostępne dla instancji EMQX. Terraform automatycznie utworzy bucket GCS.

#### Windows (PowerShell):

```powershell
cd scripts
.\upload-certs.ps1
```

#### Linux/Mac:

```bash
cd scripts
chmod +x upload-certs.sh
./upload-certs.sh
```

**LUB ręcznie przez gsutil:**

```bash
# Pobierz nazwę bucketa z outputs Terraform (po apply) lub użyj:
BUCKET_NAME="emqx-certificates-bucket-iot-proj-482921"

# Upload certyfikatów serwera
gsutil cp certs/emqx-server.key gs://$BUCKET_NAME/
gsutil cp certs/emqx-server.crt gs://$BUCKET_NAME/
gsutil cp certs/ca.crt gs://$BUCKET_NAME/ca.pem
```

**UWAGA**: Certyfikaty klienta (`device-001.*`) pozostają lokalnie i są używane przez klientów MQTT.

### Krok 5: Wdrożenie infrastruktury

```bash
# Inicjalizacja Terraform
terraform init

# Sprawdzenie planu
terraform plan

# Wdrożenie (potwierdź wpisując 'yes')
terraform apply
```

**Czas wdrożenia**: ~5-10 minut

### Krok 6: Sprawdzenie statusu

```bash
# Sprawdź status instancji
gcloud compute instances list --filter="name~emqx"

# Sprawdź IP Load Balancera (z outputs Terraform)
terraform output load_balancer_ip_prod
terraform output load_balancer_ip_dev

# Sprawdź dostępność dashboardu
curl http://$(terraform output -raw dashboard_access_info | cut -d: -f2)/api/v5/status
```

### Krok 7: Konfiguracja hasła Dashboard

Domyślne hasło to `public`. Zmień je przez:

1. Otwórz dashboard: `http://[IP_INSTANCJI]:18083`
2. Login: `admin` / `public`
3. Ustawienia > User > Zmień hasło

**LUB przez API:**

```powershell
# Login i otrzymanie tokenu
$body = @{
    username = "admin"
    password = "public"
} | ConvertTo-Json

$response = Invoke-WebRequest -Uri "http://[IP]:18083/api/v5/login" -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
$token = ($response.Content | ConvertFrom-Json).token

# Zmiana hasła (używając tokenu)
$newPasswordBody = @{
    old_pwd = "public"
    new_pwd = "TwojeNoweHaslo"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://[IP]:18083/api/v5/users/admin" -Headers @{Authorization = "Bearer $token"} -Method Put -Body $newPasswordBody -ContentType "application/json" -UseBasicParsing
```

## 🧪 Testowanie

### Test 1: Klient z certyfikatem (powinien się połączyć)

```bash
cd mqtt-clients

# Instalacja zależności
npm install

# Uruchomienie klienta z certyfikatem
node client-with-cert.js
```

**Oczekiwany wynik**: 
- ✅ Połączenie udane
- 📤 Opublikowane wiadomości
- 📥 Otrzymane wiadomości

### Test 2: Klient bez certyfikatu (powinien zostać odrzucony)

```bash
node client-without-cert.js
```

**Oczekiwany wynik**:
- ❌ Odrzucenie połączenia
- Błąd autoryzacji/certyfikatu
- ✅ To potwierdza, że zabezpieczenie działa!

### Test 3: WebSocket Client w Dashboard

1. Otwórz dashboard: `http://[IP_INSTANCJI]:18083`
2. Przejdź do: **Tools > WebSocket Client**
3. Skonfiguruj połączenie:
   - Host: `[IP_INSTANCJI]`
   - Port: `8083`
   - Path: `/mqtt`
   - TLS: `false`
   - Client ID: `test-client`
4. Kliknij **Connect**
5. Subskrybuj temat: `test/topic` (QoS: 0)
6. Opublikuj wiadomości używając klienta Node.js lub sekcji Publish

## 📊 Monitoring

### Dashboard EMQX

- URL: `http://[IP_INSTANCJI]:18083`
- Login: `admin` / `[twoje_hasło]`

**Sekcje**:
- **Monitoring > Metrics**: Statystyki wiadomości, klientów, połączeń
- **Monitoring > Clients**: Lista połączonych klientów
- **Tools > WebSocket Client**: Testowanie połączeń MQTT

### Sprawdzanie metryk przez API

```powershell
# Login
$body = @{username = "admin"; password = "Pokemon1"} | ConvertTo-Json
$response = Invoke-WebRequest -Uri "http://[IP]:18083/api/v5/login" -Method Post -Body $body -ContentType "application/json" -UseBasicParsing
$token = ($response.Content | ConvertFrom-Json).token

# Pobierz metryki
$metrics = Invoke-RestMethod -Uri "http://[IP]:18083/api/v5/metrics" -Headers @{Authorization = "Bearer $token"} -Method Get -UseBasicParsing

# Wyświetl statystyki wiadomości
$metrics.data | Get-Member -MemberType NoteProperty | Where-Object { $_.Name -like "*message*" } | ForEach-Object {
    Write-Host "$($_.Name): $($metrics.data.$($_.Name))"
}
```

## 🔧 Rozwiązywanie problemów

### Problem: Dashboard nie odpowiada

```bash
# Sprawdź status instancji
gcloud compute instances list --filter="name~emqx"

# Sprawdź logi startup script
gcloud compute instances get-serial-port-output emqx-XXXX --zone=europe-west1-b --port=1 | grep -i "emqx\|18083\|dashboard"

# Sprawdź czy port jest otwarty
gcloud compute firewall-rules list --filter="name~emqx-dashboard"
```

### Problem: Klient nie może się połączyć

1. Sprawdź czy certyfikaty są w GCS bucket:
```bash
gsutil ls gs://emqx-certificates-bucket-iot-proj-482921/
```

2. Sprawdź czy certyfikaty klienta są w folderze `certs/`:
```bash
ls certs/device-001.*
```

3. Sprawdź logi EMQX na instancji:
```bash
gcloud compute ssh emqx-XXXX --zone=europe-west1-b --command="sudo journalctl -u emqx -n 50"
```

### Problem: "502 Bad Gateway" podczas instalacji EMQX

Startup script ma automatyczne retry i fallback do instalacji z package repository. Jeśli problem persists:

```bash
# Sprawdź logi
gcloud compute instances get-serial-port-output emqx-XXXX --zone=europe-west1-b --port=1 | grep -i "error\|failed\|emqx"

# Zrestartuj instancję
gcloud compute instances restart emqx-XXXX --zone=europe-west1-b
```

## 📁 Struktura projektu

```
.
├── main.tf                 # Główne zasoby GCP (network, VMs, load balancer)
├── variables.tf            # Definicje zmiennych
├── outputs.tf              # Output values (IP addresses, URLs)
├── provider.tf             # Konfiguracja providera GCP
├── .gitignore             # Ignorowane pliki
├── scripts/
│   ├── emqx-setup.sh      # Startup script dla instancji EMQX
│   ├── generate-certs.sh  # Generowanie certyfikatów (Linux/Mac)
│   ├── generate-certs.ps1 # Generowanie certyfikatów (Windows)
│   ├── upload-certs.sh    # Upload certyfikatów do GCS (Linux/Mac)
│   └── upload-certs.ps1   # Upload certyfikatów do GCS (Windows)
├── certs/                 # Lokalne certyfikaty (ignorowane w git)
│   ├── ca.crt, ca.key
│   ├── emqx-server.crt, emqx-server.key
│   └── device-001.crt, device-001.key
└── mqtt-clients/          # Przykładowi klienci MQTT do testów
    ├── package.json
    ├── client-with-cert.js
    └── client-without-cert.js
```

## 🔐 Bezpieczeństwo

- **TLS Client Certificate Authentication**: Wymagane dla portów 8883 i 8884
- **WebSocket**: Port 8083 bez TLS (tylko dla dashboardu/testing)
- **Firewall**: Reguły ograniczające dostęp (domyślnie: 0.0.0.0/0 - zmień w produkcji!)
- **Dashboard**: Domyślne hasło `public` - **ZMIEŃ PO INSTALACJI!**

## 📝 Ważne informacje

### Dashboard nie przechowuje historii wiadomości

EMQX Dashboard pokazuje tylko **statystyki** w czasie rzeczywistym, nie przechowuje treści wiadomości. Aby zobaczyć treść wiadomości:

1. Użyj **WebSocket Client** w dashboardzie (Tools > WebSocket Client)
2. Subskrybuj temat podczas publikacji wiadomości
3. LUB użyj funkcji **Message Stream** (wymaga włączenia w dashboardzie)

### Load Balancer IPs

Po `terraform apply` sprawdź IP adresy:
```bash
terraform output load_balancer_ip_prod   # IP dla portu 8883
terraform output load_balancer_ip_dev    # IP dla portu 8884
terraform output dashboard_access_info   # IP:port dla dashboardu
```

## 🗑️ Czyszczenie zasobów

```bash
# Usuń wszystkie zasoby GCP
terraform destroy

# Usuń bucket GCS ręcznie (jeśli nie został usunięty automatycznie)
gsutil rm -r gs://emqx-certificates-bucket-iot-proj-482921
```

## 📚 Przydatne linki

- [EMQX Documentation](https://www.emqx.io/docs)
- [GCP Terraform Provider](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [EMQX Dashboard Guide](https://www.emqx.io/docs/en/v5.3/dashboard/introduction.html)

## 📄 Licencja

Ten projekt jest przykładowym wdrożeniem infrastruktury. Dostosuj do własnych potrzeb.

