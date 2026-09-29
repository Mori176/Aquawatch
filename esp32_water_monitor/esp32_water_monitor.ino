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
//    🔁 Temperature — SIMULATED (sine wave) until hardware arrives
//    🔁 pH          — SIMULATED (sine wave) until hardware arrives
//    🔁 TDS         — SIMULATED (sine wave) until hardware arrives
//
//  TO INSTALL A REAL SENSOR (replaces its simulation):
//    1. Define its pin under section 3.
//    2. In loop(), replace its sine-wave line with the real read,
//       e.g. float temp = readDs18b20();
//    (Search for "SIMULATED" in this file — all spots are tagged.)
//
//  NOTE: The upload cadence is 15 seconds (UPLOAD_INTERVAL) and does
//        NOT change with the simulation — same two writes per cycle.
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

// Alert cooldown — prevents spamming the same alert every 15s while a
// threshold stays breached. One alert per parameter per cooldown window.
#define ALERT_COOLDOWN_MS 300000UL  // 5 minutes

// Firebase Objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

bool signupOK = false;

// Cached thresholds (read from Firebase)
float thresholdWaterMin = 30.0;   // % below this = low
float thresholdWaterMax = 100.0;  // % above this = high
float thresholdTempMin = 26.0;
float thresholdTempMax = 32.0;
float thresholdPhMin   = 7.0;
float thresholdPhMax   = 8.5;
float thresholdTdsMax  = 500.0;

// Last time each parameter sent an alert: waterlevel, temperature, pH, tds
unsigned long lastAlertSentMs[4] = {0, 0, 0, 0};

int paramIndex(const String& parameter) {
  if (parameter == "waterlevel")  return 0;
  if (parameter == "temperature") return 1;
  if (parameter == "pH")          return 2;
  if (parameter == "tds")         return 3;
  return -1;
}

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

  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/waterlevel_min")) {
    thresholdWaterMin = fbdo.floatData();
  }
  if (Firebase.RTDB.getFloat(&fbdo, basePath + "/waterlevel_max")) {
    thresholdWaterMax = fbdo.floatData();
  }
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
  Serial.printf("  Water: %.0f–%.0f %%\n", thresholdWaterMin, thresholdWaterMax);
  Serial.printf("  Temp: %.1f–%.1f °C\n", thresholdTempMin, thresholdTempMax);
  Serial.printf("  pH:   %.1f–%.1f\n", thresholdPhMin, thresholdPhMax);
  Serial.printf("  TDS:  ≤ %.0f ppm\n", thresholdTdsMax);
}

// Check thresholds and send an alert to /TANK_01/alerts if exceeded.
// Severity: 'critical' when far out of range, 'warning' when slightly out.
// A per-parameter cooldown prevents alert spam while a value stays breached.
void checkAndSendAlert(String parameter, float value) {
  String severity = "";
  String action = "";

  if (parameter == "waterlevel") {
    if (value < thresholdWaterMin) {
      severity = (value < thresholdWaterMin / 2.0) ? "critical" : "warning";
      action = "Water level low — check supply";
    } else if (value > thresholdWaterMax) {
      severity = "warning";
      action = "Water level high — possible overflow";
    }
  } else if (parameter == "temperature") {
    if (value < thresholdTempMin) {
      severity = (value < thresholdTempMin - 3.0) ? "critical" : "warning";
      action = "Heater on — temperature too low";
    } else if (value > thresholdTempMax) {
      severity = (value > thresholdTempMax + 3.0) ? "critical" : "warning";
      action = "Heater off — temperature too high";
    }
  } else if (parameter == "pH") {
    if (value < thresholdPhMin) {
      severity = (value < thresholdPhMin - 0.5) ? "critical" : "warning";
      action = "pH too low";
    } else if (value > thresholdPhMax) {
      severity = (value > thresholdPhMax + 0.5) ? "critical" : "warning";
      action = "pH too high";
    }
  } else if (parameter == "tds") {
    if (value > thresholdTdsMax) {
      severity = (value > thresholdTdsMax * 1.2) ? "critical" : "warning";
      action = "Change water — TDS too high";
    }
  }

  if (severity.length() == 0) return;  // value within range — nothing to do

  int idx = paramIndex(parameter);
  if (idx >= 0 && millis() - lastAlertSentMs[idx] < ALERT_COOLDOWN_MS) {
    Serial.println("Alert suppressed (cooldown active): " + parameter);
    return;
  }

  String alertPath = String(TANK_ID) + "/alerts";
  FirebaseJson alertJson;
  alertJson.set("parameter", parameter);
  alertJson.set("value", value);
  alertJson.set("actionTaken", action);
  alertJson.set("severity", severity);
  alertJson.set("timestamp", getTimeMs());

  if (Firebase.RTDB.pushJSON(&fbdo, alertPath, &alertJson)) {
    if (idx >= 0) lastAlertSentMs[idx] = millis();
    Serial.printf("⚠ %s alert: %s = %.1f (%s)\n",
                  severity.c_str(), parameter.c_str(), value, action.c_str());
  } else {
    Serial.println("❌ Failed to send alert: " + fbdo.errorReason());
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

    // ── SIMULATED SENSORS (temperature / pH / TDS) ───────────────
    // NOTE: Hardware not installed yet. These sine-wave formulas make the
    //       values drift slowly and realistically so the whole pipeline
    //       (device → Firebase → mobile + web) can be tested and demoed.
    //       Values are deliberately kept INSIDE the alert thresholds.
    //       When real sensors arrive: delete these lines and read the
    //       actual pins instead (see section 3 pin suggestions).
    //       This costs nothing — millis() is just the chip clock, and
    //       the upload cadence (15 s) is unchanged.
    float temp = 28.0 + sin(millis() / 600000.0)   * 1.5;  // 26.5–29.5 °C
    float ph   = 7.5  + sin(millis() / 900000.0)   * 0.3;  // 7.2–7.8
    float tds  = 450.0 + sin(millis() / 1200000.0) * 40.0; // 410–490 ppm

    // --- 3. WRITE LATEST READING TO /tank_status ---
    // (Worker dashboard reads this for live display)
    FirebaseJson latestJson;
    latestJson.set("waterlevel", waterPercent);
    latestJson.set("temperature", temp);   // SIMULATED until sensor arrives
    latestJson.set("ph", ph);              // SIMULATED until sensor arrives
    latestJson.set("tds", tds);            // SIMULATED until sensor arrives
    latestJson.set("timestamp", nowMs);

    if (Firebase.RTDB.setJSON(&fbdo, "tank_status", &latestJson)) {
      Serial.println("Data sent to Firebase (latest)");
    } else {
      Serial.println("Failed to send latest: " + fbdo.errorReason());
    }

    // --- 4. APPEND TO HISTORY ---
    // (Admin web dashboard charts read from /TANK_01/history)
    FirebaseJson histJson;
    histJson.set("waterlevel", waterPercent);
    histJson.set("temperature", temp);     // SIMULATED until sensor arrives
    histJson.set("ph", ph);                // SIMULATED until sensor arrives
    histJson.set("tds", tds);              // SIMULATED until sensor arrives
    histJson.set("timestamp", nowMs);

    String historyPath = String(TANK_ID) + "/history";
    if (Firebase.RTDB.pushJSON(&fbdo, historyPath, &histJson)) {
      Serial.println("Data appended to history");
    } else {
      Serial.println("Failed to append history: " + fbdo.errorReason());
    }

    // --- 5. CHECK THRESHOLDS & SEND ALERTS ---
    // (The Cloud Function pushes these alerts to worker phones.)
    // Simulated values stay inside thresholds, so these normally stay
    // quiet — but they're live, so manipulating a threshold in Firebase
    // (e.g. tds_max = 400) demonstrably fires a real alert + push.
    checkAndSendAlert("waterlevel", waterPercent);  // real sensor
    checkAndSendAlert("temperature", temp);         // SIMULATED
    checkAndSendAlert("pH", ph);                    // SIMULATED
    checkAndSendAlert("tds", tds);                  // SIMULATED

  }

  // --- 6. PERIODIC THRESHOLD REFRESH ---
  static unsigned long lastThresholdFetch = 0;
  if (millis() - lastThresholdFetch > 60000) {  // every 60 seconds
    fetchThresholds();
    lastThresholdFetch = millis();
  }

  delay(UPLOAD_INTERVAL);
}
