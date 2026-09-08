# 🐟 AquaWatch — IoT Aquaculture Water Quality Monitoring System

**Final Year Project · UniKL MIIT**

AquaWatch is an end-to-end IoT system that monitors water quality for Asian Seabass (*Lates calcarifer*) aquaculture tanks in real time — from physical sensors, through the cloud, to the screens of farm workers and administrators.

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=flat&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?style=flat&logo=firebase&logoColor=black)
![ESP32](https://img.shields.io/badge/ESP32-000000?style=flat&logo=espressif&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?style=flat&logo=dart&logoColor=white)

---

## 📐 System Architecture

```
┌──────────────────┐         ┌─────────────────────────┐
│      ESP32       │─write──▶│                         │
│  (water sensors) │         │    Firebase Realtime    │
└──────────────────┘         │        Database          │
                             │                         │
┌──────────────────┐─r/w────▶│  tank_status             │
│  ADMIN WEB APP   │         │  TANK_01/sensors         │
│  (thresholds,    │         │  TANK_01/alerts          │
│   sensor config, │         │  TANK_01/reports         │
│   reports)       │         │  TANK_01/config/*        │
└──────────────────┘         │  users/<uid>             │
                             └───────────┬─────────────┘
                                         │ live streams
                                         ▼
                             ┌─────────────────────────┐
                             │    WORKER MOBILE APP    │
                             │  (Flutter · this repo)  │
                             └─────────────────────────┘
```

Every component communicates **only through Firebase** — no direct device-to-device links. This makes the system fully decoupled: the admin can change thresholds and the worker's app updates within seconds, with no app update required.

---

## 🧩 Components

| Component | Technology | Branch | Status |
|---|---|---|---|
| **Worker Mobile App** | Flutter · Firebase | `MobileApp` | ✅ Active |
| **ESP32 Firmware** | C++ (Arduino) | `MobileApp` (`esp32_water_monitor/`) | ✅ Active |
| **Admin Web App** | Web · Firebase | separate repo | 🚧 In progress |

---

## 📱 Worker Mobile App Features

- **Live Monitor** — real-time TDS, water level, pH, and temperature with STABLE / CAUTION tags driven by admin-configured thresholds
- **Connection indicator** — LIVE / OFFLINE badge + signal bars based on sensor data freshness
- **Sensor Dashboard** — per-sensor lifecycle with unique ID, install date, 45-day lifespan countdown, and automatic status:
  - 🟢 **ACTIVE** — attached, more than 7 days of lifespan left
  - 🟡 **REPLACE** — fewer than 7 days remaining (alerts the worker)
  - 🔴 **INACTIVE** — removed by the operator or expired (alerts the worker)
- **Alerts** — filterable event history (Critical / Warning / Info) fed by the ESP32 and sensor lifecycle events
- **Remark Reports** — capture camera photos or attach gallery images, describe incidents with sensor ID, and send to the admin (images stored in Firebase Storage)
- **Report History** — every sent report with zoomable photo attachments
- **Notification Settings** — per-operator push, sound, and vibration preferences synced to their account
- **Worker-only access** — administration lives exclusively in the web app

---

## 🔥 Firebase Realtime Database Structure

```
tank_status/                 ← live readings (ESP32, every 15s)
  waterlevel, temperature, ph, tds, timestamp

TANK_01/
  sensors/<id>/              ← sensor lifecycle (installedAt, lifespanDays,
    type, installedAt,        45-day countdown, auto-computed status)
    lifespanDays, expiresAt, status, removedAt
  alerts/<pushId>/           ← threshold breaches + sensor events
    parameter, value, actionTaken, severity, timestamp
  reports/<pushId>/          ← worker remark reports
    issue, sensorId, notes, imageUrls[], timestamp
  config/
    thresholds/              ← ph_min, ph_max, temp_min, temp_max, tds_max
    sensor_lifespan/         ← per-parameter lifespan (months)

users/<uid>/
  name, operatorId, createdAt
  fcmToken                   ← push notification target
  settings/                  ← push, sound, vibration
```

---

## 🚀 Getting Started

### Worker Mobile App

```bash
cd my_fish_app
flutter pub get
flutter run
```

1. Create a worker account in Firebase Console → **Authentication**
2. Log in from the app (or register in-app)
3. Ensure the Firebase project rules allow authenticated reads/writes

### ESP32 Firmware

1. Open `esp32_water_monitor/esp32_water_monitor.ino` in Arduino IDE
2. Set your Wi-Fi credentials and install the `Firebase ESP Client` library
3. Flash to the ESP32 — readings appear in Firebase every 15 seconds

> The `TANK_01` tank ID and all Firebase paths are defined in `lib/utils/constants.dart` and must match the ESP32 firmware.

---

## 🗂️ Repository Layout

```
my_fish_app/
├── lib/
│   ├── main.dart              # entry point — Firebase + notifications init
│   ├── models/                # typed data shapes (SensorData, SensorInfo, Report…)
│   ├── screen/                # one file per screen (login, dashboard, sensors…)
│   ├── services/              # the ONLY files that touch Firebase
│   ├── utils/                 # constants (DB paths), theme, navigator key
│   └── widgets/               # reusable UI elements
├── esp32_water_monitor/       # ESP32 C++ firmware
├── android/                   # Android platform config
└── pubspec.yaml               # dependencies
```

**Branches:** `MobileApp` holds the application source code. `main` is the project landing page.

---

## 🛣️ Roadmap

- [ ] Admin web app — Report Dashboard (Receive / Send)
- [ ] Cloud Function — automatic FCM push on critical alerts & sensor expiry
- [ ] Temperature, pH, and TDS sensor hardware integration
- [ ] Background push notification handling
- [ ] Automated water-change actuation via relay module

---

## 👤 Author

**Muhammad Hareez** — Final Year Project, UniKL MIIT

*Supervised academic project — built for learning and demonstration purposes.*
