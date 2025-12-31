/**
 * MQTT Client WITH TLS Certificate
 * Ten klient powinien się pomyślnie połączyć z brokerem EMQX
 */

const mqtt = require('mqtt');
const fs = require('fs');
const path = require('path');

// Konfiguracja - zmień te wartości na swoje
const BROKER_HOST = process.env.MQTT_BROKER_HOST || '35.205.143.223'; // IP Load Balancera prod
const BROKER_PORT = process.env.MQTT_BROKER_PORT || 8883;
const CLIENT_ID = process.env.MQTT_CLIENT_ID || 'test-client-with-cert';
const TOPIC = process.env.MQTT_TOPIC || 'test/topic';

// Ścieżki do certyfikatów (względem katalogu mqtt-clients)
const CERT_DIR = path.join(__dirname, '..', 'certs');
const CA_CERT = path.join(CERT_DIR, 'ca.crt');
const CLIENT_CERT = path.join(CERT_DIR, 'device-001.crt');
const CLIENT_KEY = path.join(CERT_DIR, 'device-001.key');

// Sprawdź czy certyfikaty istnieją
if (!fs.existsSync(CA_CERT) || !fs.existsSync(CLIENT_CERT) || !fs.existsSync(CLIENT_KEY)) {
  console.error('❌ BŁĄD: Certyfikaty nie znalezione!');
  console.error(`   Sprawdź czy pliki istnieją w: ${CERT_DIR}`);
  console.error(`   Wymagane pliki:`);
  console.error(`   - ${CA_CERT}`);
  console.error(`   - ${CLIENT_CERT}`);
  console.error(`   - ${CLIENT_KEY}`);
  process.exit(1);
}

const brokerUrl = `mqtts://${BROKER_HOST}:${BROKER_PORT}`;

console.log('🔐 MQTT Client WITH Certificate');
console.log(`📡 Łączenie z brokerem: ${brokerUrl}`);
console.log(`🆔 Client ID: ${CLIENT_ID}`);
console.log(`📝 Topic: ${TOPIC}`);
console.log('');

const client = mqtt.connect(brokerUrl, {
  clientId: CLIENT_ID,
  clean: true,
  reconnectPeriod: 0, // Wyłącz auto-reconnect dla testu
  
  // Konfiguracja TLS z certyfikatami klienta
  ca: fs.readFileSync(CA_CERT),
  cert: fs.readFileSync(CLIENT_CERT),
  key: fs.readFileSync(CLIENT_KEY),
  rejectUnauthorized: false, // Akceptuj self-signed certyfikaty (używamy własnego CA)
  
  // Opcje TLS
  protocol: 'mqtts',
  protocolVersion: 4,
});

let messageCount = 0;
const maxMessages = 3;

client.on('connect', () => {
  console.log('✅ POŁĄCZENIE UDANE! Klient z certyfikatem został zaakceptowany.');
  console.log('');
  
  // Subskrybuj temat
  client.subscribe(TOPIC, (err) => {
    if (err) {
      console.error('❌ Błąd subskrypcji:', err);
      client.end();
      return;
    }
    console.log(`📬 Subskrybowano temat: ${TOPIC}`);
    console.log('');
  });
  
  // Publikuj wiadomości testowe
  const publishInterval = setInterval(() => {
    messageCount++;
    const message = `Hello MQTT #${messageCount} - ${new Date().toISOString()}`;
    
    client.publish(TOPIC, message, { qos: 1 }, (err) => {
      if (err) {
        console.error(`❌ Błąd publikacji #${messageCount}:`, err);
      } else {
        console.log(`📤 Opublikowano #${messageCount}: ${message}`);
      }
    });
    
    if (messageCount >= maxMessages) {
      clearInterval(publishInterval);
      setTimeout(() => {
        console.log('');
        console.log('✅ Test zakończony pomyślnie!');
        client.end();
        process.exit(0);
      }, 1000);
    }
  }, 2000);
});

client.on('message', (topic, message) => {
  console.log(`📥 Otrzymano wiadomość z ${topic}: ${message.toString()}`);
});

client.on('error', (error) => {
  console.error('❌ BŁĄD połączenia:', error.message);
  if (error.code === 'ENOTFOUND') {
    console.error('   Sprawdź czy adres brokera jest poprawny');
  } else if (error.code === 'ECONNREFUSED') {
    console.error('   Broker odrzucił połączenie');
  } else if (error.message.includes('certificate')) {
    console.error('   Problem z certyfikatami - sprawdź czy są poprawne');
  }
  process.exit(1);
});

client.on('close', () => {
  console.log('🔌 Połączenie zamknięte');
});

client.on('offline', () => {
  console.log('📴 Klient offline');
});

// Timeout - jeśli nie połączy się w ciągu 10 sekund
setTimeout(() => {
  if (!client.connected) {
    console.error('❌ TIMEOUT: Nie udało się połączyć w ciągu 10 sekund');
    client.end();
    process.exit(1);
  }
}, 10000);

