#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <time.h>

// ═══════════════════════════════════════════════════════════════════
//  AquaWatch — FINAL ESP32 Firmware
//  IoT-Based Water Quality Monitoring & Predictive Alert System
//  UniKL MIIT FYP
//
//  SENSORS (all real):
//    ✅ Water Level — resistive strip, GPIO 17 (power) / 34 (signal)
//    ✅ Temperature — DS18B20, GPIO 32 (OneWire + 4.7kΩ pull-up)
//    ✅ pH — analog module, GPIO 35 (calibrate PH_OFFSET!)
//    ✅ TDS — analog module, GPIO 33 (temp-compensated formula)
//
//  Every reading goes to:
//    tank_status            (live view: mobile + web dashboards)
//    TANK_01/history        (trend charts + predictive analytics)
//    TANK_01/alerts         (threshold breaches -> Cloud Function -> push)
//
//  Reading frequency is dynamic: TANK_01/config/interval_seconds,
//  changeable from the mobile app; applied within ~60 s.
// ═══════════════════════════════════════════════════════════════════

// 1. Wi-Fi Credentials (keep SSID plain ASCII — no apostrophes/emoji!)
#define WIFI_SSID        "ezree17@unifi"
#define WIFI_PASSWORD    "ezree8877"
// Backup hotspot — rename the phone to something plain before using:
// #define WIFI_SSID        "MoriPhone"
// #define WIFI_PASSWORD    "yourhotspotpassword"

// 2. Firebase Credentials
#define API_KEY          "AIzaSyAiHatyHKL8pKdpH5quGWD3ExcomaYFEXE"
#define DATABASE_URL     "https://myfishapp-4e3e6-default-rtdb.asia-southeast1.firebasedatabase.app/"

// 3. Sensor Pins
#define POWER_PIN  17   // Water level sensor power (pulsed, anti-corrosion)
#define SIGNAL_PIN 34   // Water level signal (analog, input-only pin)
#define TEMP_PIN   32   // DS18B20 data (OneWire)
#define PH_PIN     35   // pH module signal (analog, input-only pin)
#define TDS_PIN    33   // TDS module signal (analog)

// 4. Constants
#define TANK_ID                  "TANK_01"
#define DEFAULT_UPLOAD_INTERVAL_MS 15000UL  // default; Firebase overrides
#define MIN_UPLOAD_INTERVAL_MS     10000UL  // 10 s safety floor
#define NTP_SERVER               "pool.ntp.org"
#define GMT_OFFSET_SEC           28800      // UTC+8 (Malaysia)
#define ALERT_COOLDOWN_MS        300000UL   // 5 min per parameter

// ── CALIBRATION CONSTANTS (adjust during setup) ────────────────────
// pH: dip the probe in pH 7.00 buffer, read the printed pH, then set
//     PH_OFFSET = (7.00 - printed value). Repeat until it reads 7.00.
#define PH_OFFSET   0.00
// Water level: note the printed RAW value with the strip dry (= empty)
// and fully submerged (= full), then enter them here for a true 0–100%.
#define WL_RAW_EMPTY  0
#define WL_RAW_FULL   4095

// Firebase Objects
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// Temperature sensor
OneWire oneWire(TEMP_PIN);
DallasTemperature ds18b20(&oneWire);

bool signupOK = false;

// Dynamic upload interval (seconds), fetched from Firebase.
unsigned long uploadIntervalMs = DEFAULT_UPLOAD_INTERVAL_MS;

// Cached thresholds (read from Firebase / TANK_01/config/thresholds)
float thresholdWaterMin = 30.0;
float thresholdWaterMax = 100.0;
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

// ── Helpers ─────────────────────────────────────────────────────────

// 64-bit epoch milliseconds (a 32-bit value would overflow).
int64_t getTimeMs() {
  time_t now = time(nullptr);
  if (now < 100000) return (int64_t)millis();  // NTP not synced yet
  return (int64_t)now * 1000LL;
}

// Median-of-5 analog sample — rejects electrical noise spikes.
int medianAnalogRead(int pin) {
  int s[5];
  for (int i = 0; i < 5; i++) {
    s[i] = analogRead(pin);
    delay(10);
  }
  for (int i = 1; i < 5; i++) {
    int key = s[i], j = i - 1;
    while (j >= 0 && s[j] > key) { s[j + 1] = s[j]; j--; }
    s[j + 1] = key;
  }
  return s[2];
}

// ── Sensor readers (each keeps a last-good value; NAN = never valid) ─

float lastGoodTempC = NAN;
float lastGoodPh    = NAN;
float lastGoodTds   = NAN;

// DS18B20. On error returns the last good value (or NAN).
float readTemperatureC() {
  ds18b20.requestTemperatures();
  float t = ds18b20.getTempCByIndex(0);
  if (t == DEVICE_DISCONNECTED_C || t < -50.0 || t > 100.0) {
    return lastGoodTempC;
  }
  lastGoodTempC = t;
  return t;
}

// Water level as a 0–100 % reading, median-filtered, pulsed power.
int readWaterPercent(int* rawOut = nullptr) {
  digitalWrite(POWER_PIN, HIGH);
  delay(100);
  int raw = medianAnalogRead(SIGNAL_PIN);
  digitalWrite(POWER_PIN, LOW);
  if (rawOut) *rawOut = raw;
  return map(raw, WL_RAW_EMPTY, WL_RAW_FULL, 0, 100);
}

// pH from the analog module. Returns NAN when the signal is pegged
// (probe/module disconnected). Formula: pH = 3.5 × V + PH_OFFSET —
// calibrate PH_OFFSET with the pH 7.00 buffer (see constants block).
float readPh(float* voltageOut = nullptr) {
  int raw = medianAnalogRead(PH_PIN);
  float voltage = raw * 3.3 / 4095.0;
  if (voltageOut) *voltageOut = voltage;
  if (raw < 50 || raw > 4040) return lastGoodPh;  // pegged = not connected
  float ph = 3.5 * voltage + PH_OFFSET;
  if (ph < 0.0 || ph > 14.0) return lastGoodPh;   // physically impossible
  lastGoodPh = ph;
  return ph;
}

// TDS via the standard DFRobot-style conversion, temperature-compensated
// with the live DS18B20 reading (falls back to 25 °C if temp is invalid).
float readTds(float temperatureC, float* voltageOut = nullptr) {
  int raw = medianAnalogRead(TDS_PIN);
  float voltage = raw * 3.3 / 4095.0;
  if (voltageOut) *voltageOut = voltage;
  if (raw < 50 || raw > 4040) return lastGoodTds;  // pegged = not connected

  float temp = isnan(temperatureC) ? 25.0 : temperatureC;
  float compensation = 1.0 + 0.02 * (temp - 25.0);
  float v = voltage / compensation;
  float tds = (133.42 * v * v * v - 255.86 * v * v + 857.39 * v) * 0.5;
  if (tds < 0) tds = 0;
  lastGoodTds = tds;
  return tds;
}

// ── Firebase config fetches ─────────────────────────────────────────

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
  Serial.printf("  Temp:  %.1f–%.1f °C\n", thresholdTempMin, thresholdTempMax);
  Serial.printf("  pH:    %.1f–%.1f\n", thresholdPhMin, thresholdPhMax);
  Serial.printf("  TDS:   ≤ %.0f ppm\n", thresholdTdsMax);
}

void fetchUploadInterval() {
  if (!Firebase.ready() || !signupOK) return;
  if (Firebase.RTDB.getInt(&fbdo, String(TANK_ID) + "/config/interval_seconds")) {
    int secs = fbdo.intData();
    if (secs < 10) secs = 10;
    uploadIntervalMs = (unsigned long)secs * 1000UL;
    Serial.printf("Upload interval set to %d s\n", secs);
  }
}

// ── Alerts ──────────────────────────────────────────────────────────

// Severity: 'critical' when far out of range, 'warning' when slightly
// out. One alert per parameter per 5-minute cooldown window.
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

  if (severity.length() == 0) return;  // within range

  int idx = paramIndex(parameter);
  if (idx >= 0 && lastAlertSentMs[idx] != 0 &&
      millis() - lastAlertSentMs[idx] < ALERT_COOLDOWN_MS) {
    return;  // cooldown active
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

// ── Setup & Loop ────────────────────────────────────────────────────

void setup() {
  Serial.begin(115200);

  analogSetAttenuation(ADC_11db);
  pinMode(POWER_PIN, OUTPUT);
  digitalWrite(POWER_PIN, LOW);

  ds18b20.begin();
  ds18b20.setResolution(12);  // 0.0625 °C steps

  // Wi-Fi with timeout — restart and retry instead of hanging forever.
  Serial.print("Connecting to Wi-Fi");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long wifiStart = millis();
  while (WiFi.status() != WL_CONNECTED) {
    if (millis() - wifiStart > 20000UL) {
      Serial.println("\nWi-Fi failed — check SSID/password. Restarting...");
      delay(1000);
      ESP.restart();
    }
    Serial.print(".");
    delay(300);
  }
  Serial.println("\nWi-Fi Connected!");

  configTime(GMT_OFFSET_SEC, 0, NTP_SERVER);

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;

  if (Firebase.signUp(&config, &auth, "", "")) {
    Serial.println("Firebase Auth Successful");
    signupOK = true;
  } else {
    Serial.printf("Firebase Auth Failed: %s\n",
                  config.signer.signupError.message.c_str());
  }

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  fetchThresholds();
  fetchUploadInterval();
}

void loop() {
  unsigned long now = millis();

  // --- 1. PERIODIC CONFIG REFRESH (every 60 s) --------------------
  static unsigned long lastConfigFetch = 0;
  if (now - lastConfigFetch > 60000UL) {
    fetchThresholds();
    fetchUploadInterval();
    lastConfigFetch = now;
  }

  // --- 2. READ SENSORS + UPLOAD on the dynamic schedule -----------
  static unsigned long lastUpload = 0;
  if (Firebase.ready() && signupOK && now - lastUpload >= uploadIntervalMs) {
    lastUpload = now;

    // Read all four sensors (each guards against disconnection).
    int wlRaw = 0;
    int waterPercent = readWaterPercent(&wlRaw);
    float temp = readTemperatureC();
    const bool tempValid = !isnan(temp);
    float phVoltage = 0, tdsVoltage = 0;
    float ph = readPh(&phVoltage);
    const bool phValid = !isnan(ph);
    float tds = readTds(temp, &tdsVoltage);
    const bool tdsValid = !isnan(tds);

    // Serial report (voltages/raws printed for calibration sessions).
    Serial.printf("Water Level: %d%% (raw %d)\n", waterPercent, wlRaw);
    if (tempValid) Serial.printf("Temperature: %.1f °C\n", temp);
    else           Serial.println("⚠ DS18B20 not responding");
    if (phValid)   Serial.printf("pH: %.2f (V=%.2f)\n", ph, phVoltage);
    else           Serial.println("⚠ pH module not responding");
    if (tdsValid)  Serial.printf("TDS: %.0f ppm (V=%.2f)\n", tds, tdsVoltage);
    else           Serial.println("⚠ TDS module not responding");

    int64_t nowMs = getTimeMs();

    // --- Write live reading to /tank_status ----------------------
    FirebaseJson latestJson;
    latestJson.set("waterlevel", waterPercent);
    if (tempValid) latestJson.set("temperature", temp);
    if (phValid)   latestJson.set("ph", ph);
    if (tdsValid)  latestJson.set("tds", tds);
    latestJson.set("timestamp", nowMs);

    if (Firebase.RTDB.setJSON(&fbdo, "tank_status", &latestJson)) {
      Serial.println("Data sent to Firebase (latest)");
    } else {
      Serial.println("Failed to send latest: " + fbdo.errorReason());
    }

    // --- Append to history (charts + analytics) ------------------
    FirebaseJson histJson;
    histJson.set("waterlevel", waterPercent);
    if (tempValid) histJson.set("temperature", temp);
    if (phValid)   histJson.set("ph", ph);
    if (tdsValid)  histJson.set("tds", tds);
    histJson.set("timestamp", nowMs);

    String historyPath = String(TANK_ID) + "/history";
    if (Firebase.RTDB.pushJSON(&fbdo, historyPath, &histJson)) {
      Serial.println("Data appended to history");
    } else {
      Serial.println("Failed to append history: " + fbdo.errorReason());
    }

    // --- Threshold checks -> alerts -> phone push ----------------
    checkAndSendAlert("waterlevel", waterPercent);
    if (tempValid) checkAndSendAlert("temperature", temp);
    if (phValid)   checkAndSendAlert("pH", ph);
    if (tdsValid)  checkAndSendAlert("tds", tds);
  }
}
