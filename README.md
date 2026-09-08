# AquaMonitor — IoT Aquaculture Water Quality Monitoring System
**FYP | UniKL MIIT | Flutter + Firebase + ESP32**

---

## Architecture

```
┌─────────────────┐      ┌──────────────────────────┐
│  ESP32 firmware  │ ───► │    Firebase RTDB          │
│  (reads sensors) │      │  tank_status             │
└─────────────────┘      │  TANK_01/history          │
                         │  TANK_01/alerts           │
┌─────────────────┐      │  TANK_01/config/…        │
│ Admin web app    │ ◄──► │  users                   │
│ (separate repo)  │      └──────────────────────────┘
└─────────────────┘              ▲
                                 │
                        ┌─────────────────┐
                        │  Worker app     │  ← this project
                        │  (Flutter)      │
                        └─────────────────┘
```

- **Worker mobile app (this repo)** — reads live readings + sensor lifespan only.
- **Admin web app (separate repo)** — sets sensor lifespan (`TANK_01/config/sensor_lifespan`), configures thresholds, and pulls data dumps every 5 minutes.
- **ESP32 firmware** (`esp32_water_monitor/`) — reads water level sensor, writes readings to Firebase.

---

## Project Structure

```
lib/
├── main.dart                    # App entry point, Firebase + Notification init
├── firebase_options.dart        # Auto-generated Firebase config
├── models/
│   ├── sensor_data.dart         # SensorData model (temp, pH, TDS, water level)
│   └── sensor_lifespan.dart     # SensorLifespan model (months, set by admin)
├── screen/
│   ├── login.dart               # Worker login + FCM token save
│   └── worker_dashboard.dart    # Live readings + lifespan badges
├── services/
│   ├── auth_service.dart        # Firebase Auth wrapper
│   ├── database_service.dart    # Firebase RTDB streams + writes
│   └── notification_service.dart# FCM init + token save
└── utils/
    ├── constants.dart           # Firebase paths, tank ID
    └── theme.dart               # Material 3 theme
```

---

## Firebase Database Structure (matches ESP32)

```
/tank_status/           ← ESP32 writes current readings here
  waterlevel: 45          (percentage 0–100)
  timestamp: 1716000000000  (epoch ms)

/TANK_01/
  history/              ← ESP32 appends every 15 seconds
    <push_key>/
      waterlevel, timestamp
  alerts/               ← ESP32 writes when a threshold is exceeded
    <push_key>/
      parameter, value, actionTaken, timestamp
  config/
    thresholds/         ← thresholds for ESP32 alert checks
      ph_min, ph_max, temp_min, temp_max, tds_max, updated_at
    sensor_lifespan/    ← set by the admin web app (months)
      waterLevel: 6
      temperature: 6
      ph: 6
      tds: 6

/users/
  <uid>/
    fcmToken: "..."     ← worker device token for push alerts
```

> **TANK_ID** is set in `lib/utils/constants.dart` → `AppConstants.tankId`.
> The `sensor_lifespan` fields use camelCase (`waterLevel`, `temperature`, `ph`, `tds`).

---

## Worker App — Setup Steps

1. **Open in Android Studio / VS Code**
   ```
   flutter pub get
   ```

2. **Verify Tank ID** — `lib/utils/constants.dart` → `tankId` matches your ESP32.

3. **Run on Android**
   ```
   flutter run
   ```
   `google-services.json` is included for project `myfishapp-4e3e6`.

4. **Create worker accounts in Firebase Console**
   - Firebase → Authentication → Add user
   - Log in from the app — the FCM token is saved to `users/<uid>/fcmToken` automatically.

---

## ESP32 Firmware

Located at `esp32_water_monitor/esp32_water_monitor.ino`.

- Currently only the **water level** sensor is wired (GPIO 17 power, GPIO 34 signal).
- Temperature, pH, and TDS are placeholders. To add them, search the file for `NOTE:` — each spot shows what to uncomment.
- Timestamps use 64-bit epoch milliseconds (via NTP) to avoid overflow.
