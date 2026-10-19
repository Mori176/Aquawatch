#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>

// ═══════════════════════════════════════════════════════════════════
//  AquaWatch — CONNECTIVITY / WATER-LEVEL TEST SKETCH
//  Purpose: quick hardware sanity check only (Wi-Fi, Firebase auth,
//  water-level sensor). For the real system, flash
//  esp32_water_monitor.ino instead.
// ═══════════════════════════════════════════════════════════════════

// 1. Wi-Fi credentials
#define WIFI_SSID        "ezree17@unifi"
#define WIFI_PASSWORD    "ezree8877"

// 2. Firebase credentials
#define API_KEY          "AIzaSyAiHatyHKL8pKdpH5quGWD3ExcomaYFEXE"
#define DATABASE_URL     "https://myfishapp-4e3e6-default-rtdb.asia-southeast1.firebasedatabase.app/"

// 3. Sensor pins
#define POWER_PIN  17
#define SIGNAL_PIN 34

// 4. Constants
#define UPLOAD_INTERVAL  15000          // 15 s — same cadence as the real firmware
#define NTP_SERVER       "pool.ntp.org"
#define GMT_OFFSET_SEC   28800           // UTC+8 (Malaysia)
#define WIFI_TIMEOUT_MS  20000UL

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool signupOK = false;

// Median-of-5 sampling — rejects electrical noise spikes and gives a
// stable percentage. The sensor is powered only while sampling.
int readWaterPercent() {
  int samples[5];

  digitalWrite(POWER_PIN, HIGH);
  delay(100);  // let the sensor stabilise
  for (int i = 0; i < 5; i++) {
    samples[i] = analogRead(SIGNAL_PIN);
    delay(10);
  }
  digitalWrite(POWER_PIN, LOW);

  // Insertion sort (tiny array) then take the middle value.
  for (int i = 1; i < 5; i++) {
    int key = samples[i];
    int j = i - 1;
    while (j >= 0 && samples[j] > key) {
      samples[j + 1] = samples[j];
      j--;
    }
    samples[j + 1] = key;
  }

  return map(samples[2], 0, 4095, 0, 100);
}

// 64-bit epoch milliseconds (never a 32-bit value — it would overflow).
int64_t getTimeMs() {
  time_t now = time(nullptr);
  if (now < 100000) return (int64_t)millis();  // NTP not synced yet
  return (int64_t)now * 1000LL;
}

void setup() {
  Serial.begin(115200);
  delay(200);

  analogSetAttenuation(ADC_11db);
  pinMode(POWER_PIN, OUTPUT);
  digitalWrite(POWER_PIN, LOW);

  // ── Wi-Fi with a timeout (no silent forever-hang) ──────────────
  Serial.print("Connecting to Wi-Fi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < WIFI_TIMEOUT_MS) {
    Serial.print(".");
    delay(300);
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\n❌ Wi-Fi failed. Check SSID/password, then reset the board.");
    return;
  }
  Serial.println("\n✅ Wi-Fi connected — IP: " + WiFi.localIP().toString());

  // ── NTP time (so timestamps are real, not uptime) ──────────────
  configTime(GMT_OFFSET_SEC, 0, NTP_SERVER);

  // ── Firebase ───────────────────────────────────────────────────
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("✅ Firebase auth OK");
    signupOK = true;
  } else {
    Serial.printf("❌ Firebase auth failed: %s\n",
                  config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
}

void loop() {
  if (!Firebase.ready() || !signupOK) {
    Serial.println("… waiting for Firebase");
    delay(2000);
    return;
  }

  int waterPercent = readWaterPercent();
  int64_t nowMs = getTimeMs();

  // Write the whole node as JSON so the timestamp is always present
  // (the mobile app uses it for its LIVE / OFFLINE indicator).
  FirebaseJson status;
  status.set("waterlevel", waterPercent);
  status.set("timestamp", nowMs);

  if (Firebase.RTDB.setJSON(&fbdo, "tank_status", &status)) {
    Serial.printf("✅ waterlevel = %d %%   ts = %lld\n",
                  waterPercent, (long long)nowMs);
  } else {
    Serial.println("❌ Send failed: " + fbdo.errorReason());
  }

  delay(UPLOAD_INTERVAL);
}
