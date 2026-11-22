# AquaWatch — Entity Relationship Diagram

Paste the code block below into **https://mermaid.live** → it renders instantly → click **Actions → PNG** to export an image for your report.

```mermaid
erDiagram
    USER {
        string uid PK
        string name
        string operatorId
        string fcmToken
        bool settingsPush
        bool settingsSound
        bool settingsVibration
        int createdAtMs
    }
    ADMIN {
        string uid PK
        bool isAdmin
    }
    LIVE_READING {
        double waterlevel
        double temperature
        double ph
        double tds
        int timestampMs
    }
    HISTORY_READING {
        string pushId PK
        double waterlevel
        double temperature
        double ph
        double tds
        int timestampMs
    }
    THRESHOLD_CONFIG {
        double phMin
        double phMax
        double tempMin
        double tempMax
        double tdsMax
        double waterlevelMin
        double waterlevelMax
        int updatedAtMs
    }
    INTERVAL_CONFIG {
        int intervalSeconds
    }
    SENSOR {
        string sensorId PK
        string type
        int installedAtMs
        int lifespanDays
        int expiresAtMs
        string status
        int removedAtMs
    }
    ALERT {
        string pushId PK
        string parameter
        double value
        string actionTaken
        string severity
        int timestampMs
    }
    REPORT {
        string pushId PK
        string issue
        string sensorId FK
        string notes
        string imageUrls
        int timestampMs
    }
    SENT_MESSAGE {
        string pushId PK
        string subject
        string message
        string sensorId FK
        string workerId FK
        int timestampMs
    }
    REPORT_IMAGE {
        string downloadUrl PK
        string reportId FK
    }

    USER ||--o{ REPORT : "submits"
    ADMIN ||--o{ SENT_MESSAGE : "sends to worker"
    USER ||--o| ADMIN : "flagged as"
    SENSOR ||--o{ ALERT : "lifecycle transition"
    SENSOR ||--o{ REPORT : "auto-logs event"
    REPORT ||--o{ REPORT_IMAGE : "contains"
    THRESHOLD_CONFIG ||--o{ ALERT : "governs ESP32 evaluation"
    LIVE_READING ||--o{ HISTORY_READING : "appends snapshot"
    INTERVAL_CONFIG ||--|| LIVE_READING : "controls cadence"
    ALERT }o--o{ USER : "pushed via FCM"
    THRESHOLD_CONFIG |..o{ HISTORY_READING : "predictor evaluates TDS trend"
```

## Notes for the report caption

- Firebase Realtime Database is a NoSQL tree; this is a **logical** ERD — references (`sensorId`, `uid`, `workerId`) are application-maintained conventions, not enforced constraints.
- All timestamps are epoch milliseconds.
- Node mapping: `users/{uid}`, `admins/{uid}`, `tank_status`, `TANK_01/history`, `TANK_01/config/thresholds`, `TANK_01/config/interval_seconds`, `TANK_01/sensors/{id}`, `TANK_01/alerts`, `TANK_01/reports`, `TANK_01/reports/sent`. Images: Firebase Storage `TANK_01/reports/{id}/`.
