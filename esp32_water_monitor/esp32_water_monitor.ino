#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>

// ═══════════════════════════════════════════════════════════════════
//  AquaMonitor — ESP32 Water Quality Monitoring
//  UniKL MIIT FYP
//
//  SENSOR STATUS:
//    ✅ Water Level — connected (GPIO 17 power, GPIO 34 signal)
//    ❌ Temperature — not yet connected
//    ❌ pH          — not yet connected
//    ❌ TDS         — not yet connected
//
//  TO ADD A NEW SENSOR:
//    1. Define its pin under section 3.
//    2. Replace its placeholder (0) with actual reading in loop().
//    3. Uncomment the corresponding Firebase .set() and alert lines.
//    (Search for "NOTE:" in this file — all spots are tagged.)
// ═══════════════════════════════════════════════════════════════════

// 1. Your Wi-Fi Credentials
#define WIFI_SSID        "Oppo"
#define WIFI_PASSWORD    "v27sxdkd"

// 2. Your Firebase Credentials
#define API_KEY          "AIzaSyAiHatyHKL8pKdpH5quGWD3ExcomaYFEXE"
#define DATABASE_URL     "https://myfishapp-4e3e6-default-rtdb.asia-southeast1.firebasedatabase.app/"

// 3. Sensor Pins
// NOTE: When adding new sensors, define their pins here, e.g.:
//   #define TEMP_PIN    32
//   #define PH_PIN      35
//   #define TDS_PIN     33
#define POWER_PIN  17   // Water level sensor power pin
#define SIGNAL_PIN 34   // Water level sensor signal pin (analog)

// 4. Constants
#define TANK_ID          "TANK_01"
#define UPLOAD_INTERVAL  15000  // 15 seconds between readings
#define NTP_SERVER       "pool.ntp.org"
#define GMT_OFFSET_SEC   28800  // UTC+8 (Malaysia time)

// Firebase Objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool signupOK = false;

// Cached thresholds (read from Firebase)
float thresholdTempMin = 26.0;
float thresholdTempMax = 32.0;
float thresholdPhMin   = 7.0;
float thresholdPhMax   = 8.5;
float thresholdTdsMax  = 500.0;

// NTP time retrieval — returns milliseconds since epoch (64-bit).
// NOTE: Must use int64_t. A 32-bit unsigned long overflows for
//       epoch milliseconds (value is ~1.7e12 in 2026).
int64_t getTimeMs() {
  time_t now = time(nullptr);
  if (now < 100000) {
    // NTP not synced yet — fall back to uptime (cannot overflow 64-bit)
    return (int64_t)millis();
  }
  return (int64_t)now * 1000LL;
}

// Read thresholds from Firebase /TANK_01/config/thresholds
void fetchThresholds() {
  if (!Firebase.ready() || !signupOK) return;

  String basePath = String(TANK_ID) + "/config/thresholds";

  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/temp_min")) {
    thresholdTempMin = fbdo.floatData();
  }
  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/temp_max")) {
    thresholdTempMax = fbdo.floatData();
  }
  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/ph_min")) {
    thresholdPhMin = fbdo.floatData();
  }
  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/ph_max")) {
    thresholdPhMax = fbdo.floatData();
  }
  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/tds_max")) {
    thresholdTdsMax = fbdo.floatData();
  }

  Serial.println("Thresholds fetched from Firebase.");
  Serial.printf("  Temp: %.1f–%.1f °C\n", thresholdTempMin, thresholdTempMax);
  Serial.printf("  pH:   %.1f–%.1f\n", thresholdPhMin, thresholdPhMax);
  Serial.printf("  TDS:  ≤ %.0f ppm\n", thresholdTdsMax);
}

// Check thresholds and send alert to /TANK_01/alerts if exceeded
void checkAndSendAlert(String parameter, float value) {
  bool alert = false;
  String action = "";

  if (parameter == "temperature") {
    if (value < thresholdTempMin) { alert = true; action = "Heater on"; }
    if (value > thresholdTempMax) { alert = true; action = "Heater off"; }
  } else if (parameter == "pH") {
    if (value < thresholdPhMin)   { alert = true; action = "pH too low"; }
    if (value > thresholdPhMax)   { alert = true; action = "pH too high"; }
  } else if (parameter == "tds") {
    if (value > thresholdTdsMax)  { alert = true; action = "Change water"; }
  }

  if (alert) {
    String alertPath = String(TANK_ID) + "/alerts";
    FirebaseJson alertJson;
    alertJson.set("parameter", parameter);
    alertJson.set("value", value);
    alertJson.set("actionTaken", action);
    alertJson.set("timestamp", getTimeMs());

    if (Firebase.RTDB.pushJSON(&fbdo, alertPath, &alertJson)) {
      Serial.printf("⚠ Alert sent: %s = %.1f (%s)\n", parameter.c_str(), value, action.c_str());
    } else {
      Serial.println("❌ Failed to send alert: " + fbdo.errorReason());
    }
  }
}

void setup() {
  Serial.begin(115200);

  analogSetAttenuation(ADC_11db);
  pinMode(POWER_PIN, OUTPUT);
  digitalWrite(POWER_PIN, LOW);

  // Connect to Wi-Fi
  Serial.print("Connecting to Wi-Fi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nWi-Fi Connected!");

  // Sync time via NTP
  configTime(GMT_OFFSET_SEC, 0, NTP_SERVER);

  // Configure Firebase
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("Firebase Auth Successful");
    signupOK = true;
  } else {
    Serial.printf("Firebase Auth Failed: %s\n", config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  // Pull configured thresholds from Firebase
  fetchThresholds();
}

void loop() {
  if (Firebase.ready() && signupOK) {

    // --- 1. READ THE SENSOR ---
    digitalWrite(POWER_PIN, HIGH);
    delay(100);
    int rawValue = analogRead(SIGNAL_PIN);
    digitalWrite(POWER_PIN, LOW);

    int waterPercent = map(rawValue, 0, 4095, 0, 100);

    Serial.printf("Water Level: %d%%\n", waterPercent);

    // --- 2. GET TIMESTAMP ---
    int64_t nowMs = getTimeMs();

    // ── SENSOR PLACEHOLDERS ──────────────────────────────────────
    // NOTE: Replace these with actual sensor readings when hardware is wired.
    //       For example: float temp = dht.readTemperature();
    //                    float ph   = analogRead(PH_PIN) * conversionFactor;
    //                    float tds  = analogRead(TDS_PIN) * conversionFactor;
    float temp = 0;
    float ph   = 0;
    float tds  = 0;

    // --- 3. WRITE LATEST READING TO /tank_status ---
    // (Worker dashboard reads this for live display)
    FirebaseJson latestJson;
    latestJson.set("waterlevel", waterPercent);
    latestJson.set("timestamp", nowMs);
    // NOTE: Uncomment these when temperature/pH/TDS sensors are connected:
    // latestJson.set("temperature", temp);
    // latestJson.set("ph", ph);
    // latestJson.set("tds", tds);

    if (Firebase.RTDB.setJSON(&fbdo, "tank_status", &latestJson)) {
      Serial.println("Data sent to Firebase (latest)");
    } else {
      Serial.println("Failed to send latest: " + fbdo.errorReason());
    }

    // --- 4. APPEND TO HISTORY ---
    // (Admin dashboard charts read from /TANK_01/history)
    FirebaseJson histJson;
    histJson.set("waterlevel", waterPercent);
    histJson.set("timestamp", nowMs);
    // NOTE: Uncomment these when temperature/pH/TDS sensors are connected:
    // histJson.set("temperature", temp);
    // histJson.set("ph", ph);
    // histJson.set("tds", tds);

    String historyPath = String(TANK_ID) + "/history";
    if (Firebase.RTDB.pushJSON(&fbdo, historyPath, &histJson)) {
      Serial.println("Data appended to history");
    } else {
      Serial.println("Failed to append history: " + fbdo.errorReason());
    }

    // --- 5. CHECK THRESHOLDS & SEND ALERTS ---
    // (Alerts appear in Admin Dashboard > Alert History)
    // NOTE: Uncomment when temperature/pH/TDS sensors are connected:
    // checkAndSendAlert("temperature", temp);
    // checkAndSendAlert("pH", ph);
    // checkAndSendAlert("tds", tds);

  }

  // --- 6. PERIODIC THRESHOLD REFRESH ---
  static unsigned long lastThresholdFetch = 0;
  if (millis() - lastThresholdFetch > 60000) {  // every 60 seconds
    fetchThresholds();
    lastThresholdFetch = millis();
  }

  delay(UPLOAD_INTERVAL);
}
