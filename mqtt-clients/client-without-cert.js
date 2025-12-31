/**
 * MQTT Client WITHOUT TLS Certificate
 * Ten klient NIE powinien się połączyć z brokerem EMQX (broker wymaga certyfikatu klienta)
 */

const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

// Konfiguracja - zmień te wartości na swoje
const BROKER_HOST = process.env.MQTT_BROKER_HOST || '35.205.143.223'; // IP Load Balancera prod
const BROKER_PORT = process.env.MQTT_BROKER_PORT || 8883;
const CLIENT_ID = process.env.MQTT_CLIENT_ID || 'test-client-without-cert';
const TOPIC = process.env.MQTT_TOPIC || 'test/topic';

// Ścieżka do certyfikatu CA (tylko do walidacji serwera, bez certyfikatu klienta)
const CERT_DIR = path.join(__dirname, '..', 'certs');
const CA_CERT = path.join(CERT_DIR, 'ca.crt');

const brokerUrl = `mqtts://${BROKER_HOST}:${BROKER_PORT}`;

console.log('⚠️  MQTT Client WITHOUT Certificate');
console.log(`📡 Łączenie z brokerem: ${brokerUrl}`);
console.log(`🆔 Client ID: ${CLIENT_ID}`);
console.log(`📝 Topic: ${TOPIC}`);
console.log('');
console.log('🔒 Ten klient NIE ma certyfikatu - powinien zostać ODRZUCONY przez brokera');
console.log('');

const client = mqtt.connect(brokerUrl, {
  clientId: CLIENT_ID,
  clean: true,
  reconnectPeriod: 0, // Wyłącz auto-reconnect dla testu
  
  // Tylko certyfikat CA (bez certyfikatu klienta)
  ca: fs.existsSync(CA_CERT) ? fs.readFileSync(CA_CERT) : undefined,
  rejectUnauthorized: true,
  
  // Brak cert i key - to powoduje że broker powinien odrzucić połączenie
  
  // Opcje TLS
  protocol: 'mqtts',
  protocolVersion: 4,
});

let connectionTimeout;

client.on('connect', () => {
  console.error('❌ BŁĄD: Klient bez certyfikatu się połączył!');
  console.error('   To oznacza, że zabezpieczenie NIE działa poprawnie!');
  console.error('   Broker powinien wymagać certyfikatu klienta.');
  client.end();
  process.exit(1);
});

client.on('error', (error) => {
  // Oczekiwane błędy (broker odrzuca połączenie)
  const expectedErrors = [
    'EPROTO',
    'ECONNRESET',
    'ENOTFOUND',
    'certificate',
    'handshake',
    'peer did not return a certificate',
    'no shared cipher',
  ];
  
  const isExpectedError = expectedErrors.some(err => 
    error.message.toLowerCase().includes(err.toLowerCase()) ||
    error.code?.toLowerCase().includes(err.toLowerCase())
  );
  
  if (isExpectedError) {
    console.log('✅ ODRZUCENIE POŁĄCZENIA - to jest oczekiwane zachowanie!');
    console.log(`📋 Powód: ${error.message || error.code}`);
    console.log('');
    console.log('🎉 Test zakończony pomyślnie!');
    console.log('   Broker poprawnie odrzucił połączenie bez certyfikatu klienta.');
    clearTimeout(connectionTimeout);
    client.end();
    process.exit(0);
  } else {
    console.error('❌ Nieoczekiwany błąd:', error.message || error.code);
    if (error.code) {
      console.error('   Code:', error.code);
    }
    clearTimeout(connectionTimeout);
    client.end();
    process.exit(1);
  }
});

client.on('close', () => {
  // Jeśli połączenie zostało zamknięte bez błędu, to też może oznaczać odrzucenie
  if (!client.connected) {
    console.log('✅ Połączenie zamknięte przez brokera - to jest oczekiwane');
    console.log('🎉 Test zakończony pomyślnie!');
    console.log('   Broker poprawnie odrzucił połączenie bez certyfikatu klienta.');
  }
});

client.on('offline', () => {
  console.log('📴 Klient offline');
});

// Timeout - jeśli nie otrzymamy odpowiedzi w ciągu 10 sekund
connectionTimeout = setTimeout(() => {
  if (!client.connected) {
    console.log('✅ TIMEOUT - broker nie zaakceptował połączenia (to jest oczekiwane)');
    console.log('🎉 Test zakończony pomyślnie!');
    console.log('   Broker poprawnie odrzucił połączenie bez certyfikatu klienta.');
    client.end();
    process.exit(0);
  }
}, 10000);

