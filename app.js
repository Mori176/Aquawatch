import {
  ref,
  onValue,
  push,
  set,
  update,
  get
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js";

import {
  signInWithEmailAndPassword,
  signOut,
  onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/10.12.2/firebase-auth.js";

/* ==================================================
   CONFIGURATION / THRESHOLDS (Firebase-backed)
   Source of truth: TANK_01/config/thresholds
   ================================================== */

const ACTIVE_TANK = "TANK_01";

// Flat, snake_case contract consumed by the Flutter mobile app and ESP32
// firmware. The 8 keys below (incl. updated_at) must always be present;
// extra keys are for the admin UI only and are ignored by downstream apps.
const DEFAULT_THRESHOLDS = {
  ph_min: 7.0,
  ph_max: 8.5,
  temp_min: 26.0,
  temp_max: 32.0,
  tds_max: 600.0,
  waterlevel_min: 35.0,
  waterlevel_max: 100.0,
  // Admin UI extras (ignored by mobile/firmware)
  temp_critical_max: 34.0,
  ph_critical_min: 6.5,
  tds_critical_max: 900.0
};

let waterLevelMin = DEFAULT_THRESHOLDS.waterlevel_min;
let waterLevelMax = DEFAULT_THRESHOLDS.waterlevel_max;

/* ==================================================
   AUTH
   ================================================== */

/* ---- Login UI helpers (inline feedback, no browser alerts) ---- */

function showLoginError(message) {
  const el = document.getElementById("loginError");
  if (!el) return;
  el.textContent = message;
  el.classList.remove("hidden");
}

function clearLoginError() {
  const el = document.getElementById("loginError");
  if (!el) return;
  el.textContent = "";
  el.classList.add("hidden");
}

function setLoginBusy(busy) {
  const btn = document.querySelector("#loginPage .login-btn");
  if (!btn) return;
  btn.disabled = busy;
  btn.textContent = busy ? "Signing in..." : "Login";
}

// Turn Firebase Auth error codes into clear, human-readable messages.
function describeAuthError(error) {
  switch (error && error.code) {
    case "auth/invalid-email":
      return "That email address is not valid.";
    case "auth/user-disabled":
      return "This account has been disabled. Contact the system administrator.";
    case "auth/user-not-found":
      return "No account exists with that email.";
    case "auth/wrong-password":
      return "Incorrect password. Please try again.";
    case "auth/invalid-credential":
      return "Incorrect email or password. Please try again.";
    case "auth/too-many-requests":
      return "Too many failed attempts. Please wait a moment and try again.";
    case "auth/network-request-failed":
      return "Network error. Check your internet connection and try again.";
    case "auth/operation-not-allowed":
      return "Email/password sign-in is disabled in Firebase.";
    default:
      return "Unable to sign in. " + ((error && error.message) || "Please try again.");
  }
}

// Admins are listed in Firebase at admins/<uid> = true. Only the account
// owner may read their own flag; no client may ever write it.
async function isAdminAccount(uid) {
  if (!uid) return false;
  const snapshot = await get(ref(db, `admins/${uid}`));
  return snapshot.val() === true;
}

/* ==================================================
   AUTH — sign-in only, restricted to accounts listed
   in Firebase at admins/<uid>. Admin accounts are
   created directly in the Firebase console, never here.
   Worker accounts (created in the mobile app) are not
   listed there, so they cannot open this dashboard.
   ================================================== */

function showLoginScreen() {
  document.getElementById("loginPage").style.display = "flex";
  document.getElementById("adminApp").classList.add("hidden");
}

function showDashboard() {
  document.getElementById("loginPage").style.display = "none";
  document.getElementById("adminApp").classList.remove("hidden");
}

window.loginAdmin = async function(event) {
  event.preventDefault();

  const email = document.getElementById("loginEmail").value.trim();
  const password = document.getElementById("loginPassword").value;

  clearLoginError();

  if (!email || !password) {
    showLoginError("Please enter both your email and password.");
    return;
  }

  setLoginBusy(true);

  try {
    // Success/failure of the session is handled by onAuthStateChanged below,
    // so a persisted login is treated exactly the same as a fresh one.
    await signInWithEmailAndPassword(window.auth, email, password);
  } catch (error) {
    showLoginError(describeAuthError(error));
  } finally {
    setLoginBusy(false);
  }
};

// Single source of truth for "am I allowed in?". Runs on load (restoring a
// saved session) and after every sign-in/sign-out.
onAuthStateChanged(window.auth, async (user) => {
  if (!user) {
    showLoginScreen();
    return;
  }

  try {
    const admin = await isAdminAccount(user.uid);
    if (!admin) {
      await signOut(window.auth);
      showLoginError("This account does not have admin access.");
      showLoginScreen();
      return;
    }
    showDashboard();
  } catch (checkError) {
    await signOut(window.auth);
    showLoginError("Could not verify admin access. Please check your connection and try again.");
    showLoginScreen();
  }
});

window.logoutAdmin = async function() {
  try {
    await signOut(window.auth);
  } catch (error) {
    // Sign-out is best-effort; clear the UI regardless.
  }
  document.getElementById("loginEmail").value = "";
  document.getElementById("loginPassword").value = "";
  clearLoginError();
  showLoginScreen();
};

/* ==================================================
   NAVIGATION
   ================================================== */

window.showPage = function(pageId, button) {
  document.querySelectorAll(".page").forEach(page => {
    page.classList.remove("active");
  });

  document.querySelectorAll(".nav-link").forEach(link => {
    link.classList.remove("active");
  });

  document.getElementById(pageId).classList.add("active");
  button.classList.add("active");

  const titles = {
    dashboard: "Dashboard",
    analytics: "Historical Analytics",
    alerts: "Alert History",
    communication: "Report Dashboard",
    predictor: "Predictive Estimator",
    sensors: "Sensor Dashboard",
    settings: "System Configuration"
  };

  document.getElementById("pageTitle").textContent = titles[pageId];
};

/* ==================================================
   HELPERS
   ================================================== */

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str == null ? "" : String(str);
  return div.innerHTML;
}

function formatTimestamp(ts) {
  if (!ts) return "-";
  // Handle both seconds (10 digits) and milliseconds (13 digits) epoch values
  const ms = String(ts).length <= 10 ? Number(ts) * 1000 : Number(ts);
  const d = new Date(ms);
  if (isNaN(d.getTime())) return "-";
  return d.toLocaleString();
}

function showToastMessage(text) {
  const toast = document.getElementById("toast");
  toast.textContent = text;
  toast.classList.add("show");

  setTimeout(() => {
    toast.classList.remove("show");
  }, 2500);
}

/* ==================================================
   SETTINGS / THRESHOLDS
   ================================================== */

const db = window.db;

const thresholdsRef = ref(db, `${ACTIVE_TANK}/config/thresholds`);

let latestThresholds = null;

function mergeThresholds(defaults, data) {
  const merged = {};
  for (const key of Object.keys(defaults)) {
    merged[key] = data && data[key] !== undefined ? data[key] : defaults[key];
  }
  return merged;
}

function populateSettingsForm(thresholds) {
  const setVal = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.value = value;
  };
  setVal("tempWarningMin", thresholds.temp_min);
  setVal("tempWarningMax", thresholds.temp_max);
  setVal("tempCriticalMax", thresholds.temp_critical_max);
  setVal("phWarningMin", thresholds.ph_min);
  setVal("phWarningMax", thresholds.ph_max);
  setVal("phCriticalMin", thresholds.ph_critical_min);
  setVal("tdsWarningMax", thresholds.tds_max);
  setVal("tdsCriticalMax", thresholds.tds_critical_max);
  setVal("wlWarningMin", thresholds.waterlevel_min);
  setVal("wlWarningMax", thresholds.waterlevel_max);
}

function updateKpiSafeRanges(thresholds) {
  const setSmall = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  };
  setSmall("tempRange", `Safe range: ${thresholds.temp_min}°C - ${thresholds.temp_max}°C`);
  setSmall("phRange", `Safe range: ${thresholds.ph_min} - ${thresholds.ph_max}`);
  setSmall("tdsRange", `Safe range: up to ${thresholds.tds_max} ppm`);
  setSmall("levelRange", `Safe range: ${thresholds.waterlevel_min} - ${thresholds.waterlevel_max} %`);
}

function refreshWaterLevelStatusFromConfig() {
  const currentWaterText = document.getElementById("levelValue").textContent;
  const currentWaterLevel = Number(currentWaterText.replace(" %", ""));
  if (!isNaN(currentWaterLevel)) {
    updateWaterLevelStatus(currentWaterLevel);
  }
}

// Load thresholds from Firebase (single source of truth). If the node does not
// exist yet, seed it with the current defaults so the admin can edit them.
onValue(thresholdsRef, (snapshot) => {
  const data = snapshot.val();

  if (data === null) {
    update(thresholdsRef, { ...DEFAULT_THRESHOLDS, updated_at: Date.now() }).catch(() => {});
    return;
  }

  const thresholds = mergeThresholds(DEFAULT_THRESHOLDS, data);

  latestThresholds = thresholds;

  waterLevelMin = Number(thresholds.waterlevel_min) || waterLevelMin;
  waterLevelMax = Number(thresholds.waterlevel_max) || waterLevelMax;

  populateSettingsForm(thresholds);
  updateKpiSafeRanges(thresholds);
  refreshWaterLevelStatusFromConfig();
  updatePredictor();
});

// Persist admin-edited thresholds back to Firebase using the flat contract.
window.saveThresholds = function() {
  const read = (id) => Number(document.getElementById(id).value);

  const thresholds = {
    ph_min: read("phWarningMin"),
    ph_max: read("phWarningMax"),
    temp_min: read("tempWarningMin"),
    temp_max: read("tempWarningMax"),
    tds_max: read("tdsWarningMax"),
    waterlevel_min: read("wlWarningMin"),
    waterlevel_max: read("wlWarningMax"),
    temp_critical_max: read("tempCriticalMax"),
    ph_critical_min: read("phCriticalMin"),
    tds_critical_max: read("tdsCriticalMax"),
    updated_at: Date.now()
  };

  set(thresholdsRef, thresholds)
    .then(() => {
      waterLevelMin = thresholds.waterlevel_min;
      waterLevelMax = thresholds.waterlevel_max;
      refreshWaterLevelStatusFromConfig();
      showToastMessage("Threshold settings saved to Firebase.");
    })
    .catch((error) => {
      alert("Failed to save thresholds: " + error.message);
    });
};

document.getElementById("tempValue").textContent = "-";
document.getElementById("phValue").textContent = "-";
document.getElementById("tdsValue").textContent = "-";

function updateWaterLevelStatus(waterLevel) {
  const waterCard = document.querySelector("#levelValue").closest(".kpi-card");
  const waterTag = waterCard.querySelector(".tag");

  waterCard.classList.remove("good-card", "warning-card", "danger-card");
  waterTag.classList.remove("good", "warning", "danger");

  if (waterLevel >= waterLevelMin && waterLevel <= waterLevelMax) {
    waterCard.classList.add("good-card");
    waterTag.classList.add("good");
    waterTag.textContent = "OPTIMAL";
  } else {
    waterCard.classList.add("danger-card");
    waterTag.classList.add("danger");
    waterTag.textContent = "CRITICAL";
  }
}

/* ==================================================
   REPORT DASHBOARD — Receive (Worker -> Admin) and
   Sent (Admin -> Worker).
   All report data is scoped under the active tank:
   TANK_01/reports          (worker reports -> Receive)
   TANK_01/reports/sent     (admin reports   -> Sent)
   ================================================== */

const receivedReportsRef = ref(db, `${ACTIVE_TANK}/reports`);
const sentReportsRef = ref(db, `${ACTIVE_TANK}/reports/sent`);

// Reserved sub-nodes under TANK_01/reports that are NOT worker reports.
function isReservedReportKey(key) {
  return key === "sent";
}

let latestReports = null;
const openedReportIds = new Set();

let latestSent = null;
const openedSentIds = new Set();

// Realtime: new worker reports appear in Receive automatically.
onValue(receivedReportsRef, (snapshot) => {
  latestReports = snapshot.val();
  renderReceiveReports(latestReports);
});

// Realtime: admin-sent reports/messages appear in Sent.
onValue(sentReportsRef, (snapshot) => {
  latestSent = snapshot.val();
  renderSentReports(latestSent);
});

window.showReportTab = function(tab, button) {
  document.querySelectorAll(".report-tab").forEach((t) => t.classList.remove("active"));
  document.getElementById("receiveTab").classList.toggle("hidden", tab !== "receive");
  document.getElementById("sentTab").classList.toggle("hidden", tab !== "sent");
  if (button) button.classList.add("active");
};

// Swap a broken attachment image for a graceful placeholder message.
window.reportImageError = function(el) {
  el.outerHTML = `<p class="report-no-img">Image could not be loaded.</p>`;
};

function firstDefined(...values) {
  for (const v of values) {
    if (v !== undefined && v !== null && v !== "") return v;
  }
  return undefined;
}

function reportWorker(report) {
  return firstDefined(report.workerId, report.worker, report.workerName, report.from, report.sender) || "Worker";
}

function reportSensor(report) {
  return firstDefined(report.sensorId, report.sensor, report.sensor_id) || "Unknown";
}

function reportIssue(report) {
  return firstDefined(report.issue) || "(No issue stated)";
}

function reportNotes(report) {
  return firstDefined(report.notes, report.description, report.text, report.message, report.details) || "(No notes)";
}

function reportTime(report) {
  return Number(firstDefined(report.timestamp, report.createdAt, report.date, report.time) || 0);
}

function reportImages(report) {
  const raw = firstDefined(report.imageUrls, report.images, report.imageUrl, report.image);
  if (!raw) return [];
  if (typeof raw === "string") return [raw];
  if (Array.isArray(raw)) return raw.filter((v) => typeof v === "string" && v);
  return Object.values(raw).filter((v) => typeof v === "string" && v);
}

function updateReceiveTabLabel() {
  const btn = document.querySelector('.report-tab[data-tab="receive"]');
  if (!btn) return;
  let unread = 0;
  if (latestReports) {
    Object.keys(latestReports).forEach((id) => {
      if (!isReservedReportKey(id) && !openedReportIds.has(id)) unread++;
    });
  }
  btn.textContent = unread > 0 ? `📥 Receive (${unread})` : "📥 Receive";
}

function updateSentTabLabel() {
  const btn = document.querySelector('.report-tab[data-tab="sent"]');
  if (!btn) return;
  let unread = 0;
  if (latestSent) {
    Object.keys(latestSent).forEach((id) => {
      if (!openedSentIds.has(id)) unread++;
    });
  }
  btn.textContent = unread > 0 ? `📤 Sent (${unread})` : "📤 Sent";
}

/* ---- Receive: reports submitted BY workers (TANK_01/reports) ---- */

function renderReceiveReports(data) {
  const container = document.getElementById("receiveList");
  container.innerHTML = "";

  if (!data) {
    container.innerHTML = `<p class="comm-empty">No reports received from workers yet.</p>`;
    updateReceiveTabLabel();
    return;
  }

  const entries = Object.entries(data)
    .filter(([reportId]) => !isReservedReportKey(reportId))
    .sort((a, b) => reportTime(b[1]) - reportTime(a[1]));

  if (entries.length === 0) {
    container.innerHTML = `<p class="comm-empty">No reports received from workers yet.</p>`;
    updateReceiveTabLabel();
    return;
  }

  entries.forEach(([reportId, report]) => {
    const worker = reportWorker(report);
    const sensor = reportSensor(report);
    const notes = reportNotes(report);
    const time = formatTimestamp(reportTime(report));
    const isRead = openedReportIds.has(reportId);

    const item = document.createElement("button");
    item.type = "button";
    item.className = "email-item";
    item.onclick = () => openReport(reportId);

    item.innerHTML = `
      <span class="email-dot ${isRead ? "" : "email-dot-unread"}"></span>
      <div class="email-content">
        <div class="email-top">
          <strong>${escapeHtml(worker)}</strong>
          <span class="email-time">${time}</span>
        </div>
        <span class="email-subject">Sensor Replacement Report · ${escapeHtml(sensor)}</span>
        <p class="email-preview">${escapeHtml(notes)}</p>
      </div>
    `;

    container.appendChild(item);
  });

  updateReceiveTabLabel();
}

window.openReport = function(reportId) {
  const report = latestReports && latestReports[reportId];
  if (!report || isReservedReportKey(reportId)) return;

  openedReportIds.add(reportId);

  const container = document.getElementById("receiveList");
  const detail = document.getElementById("reportDetail");

  const images = reportImages(report);
  const imagesHtml = images.length > 0
    ? images.map((src) => `<img src="${escapeHtml(src)}" class="report-img" alt="Attached image" onerror="reportImageError(this)">`).join("")
    : `<p class="report-no-img">No image attached to this report.</p>`;

  detail.innerHTML = `
    <div class="comm-alert-card report-detail-card">
      <div class="report-detail-header">
        <div>
          <h3>Sensor Replacement Report</h3>
          <small>From: ${escapeHtml(reportWorker(report))} · Sensor ID: ${escapeHtml(reportSensor(report))} · ${formatTimestamp(reportTime(report))}</small>
        </div>
        <button type="button" class="secondary-btn small-btn" onclick="backToInbox()">Back to Inbox</button>
      </div>
      <div class="report-detail-body">
        <p class="report-field-label">Issue</p>
        <p class="report-desc">${escapeHtml(reportIssue(report))}</p>
        <p class="report-field-label">Notes</p>
        <p class="report-desc">${escapeHtml(reportNotes(report))}</p>
        <p class="report-field-label">Attached Images</p>
        <div class="report-images">${imagesHtml}</div>
      </div>
    </div>
  `;

  container.classList.add("hidden");
  detail.classList.remove("hidden");
  updateReceiveTabLabel();
};

window.backToInbox = function() {
  const container = document.getElementById("receiveList");
  const detail = document.getElementById("reportDetail");
  detail.classList.add("hidden");
  detail.innerHTML = "";
  container.classList.remove("hidden");
};

/* ---- Sent: reports / messages sent BY the admin (TANK_01/reports/sent) ---- */

function sentWorker(report) {
  return firstDefined(report.workerId, report.worker, report.workerName, report.to) || "Worker";
}

function sentSensor(report) {
  return firstDefined(report.sensorId, report.sensor, report.sensor_id) || "Unknown";
}

function sentSubject(report) {
  return firstDefined(report.subject, report.title) || "Message";
}

function sentMessage(report) {
  return firstDefined(report.message, report.text, report.notes, report.description) || "(No message)";
}

function renderSentReports(data) {
  const container = document.getElementById("sentList");
  container.innerHTML = "";

  const emptyText = `No messages sent yet. Click "+ New Message" to send one to the worker.`;

  if (!data) {
    container.innerHTML = `<p class="comm-empty">${emptyText}</p>`;
    updateSentTabLabel();
    return;
  }

  const entries = Object.entries(data).sort((a, b) => reportTime(b[1]) - reportTime(a[1]));

  if (entries.length === 0) {
    container.innerHTML = `<p class="comm-empty">${emptyText}</p>`;
    updateSentTabLabel();
    return;
  }

  entries.forEach(([msgId, msg]) => {
    const isRead = openedSentIds.has(msgId);
    const time = formatTimestamp(reportTime(msg));

    const item = document.createElement("button");
    item.type = "button";
    item.className = "email-item";
    item.onclick = () => openSentMessage(msgId);

    item.innerHTML = `
      <span class="email-dot ${isRead ? "" : "email-dot-unread"}"></span>
      <div class="email-content">
        <div class="email-top">
          <strong>Admin</strong>
          <span class="email-time">${time}</span>
        </div>
        <span class="email-subject">${escapeHtml(sentSubject(msg))} · ${escapeHtml(sentSensor(msg))}</span>
        <p class="email-preview">${escapeHtml(sentMessage(msg))}</p>
      </div>
    `;

    container.appendChild(item);
  });

  updateSentTabLabel();
}

window.openSentMessage = function(msgId) {
  const msg = latestSent && latestSent[msgId];
  if (!msg) return;

  openedSentIds.add(msgId);

  const container = document.getElementById("sentList");
  const detail = document.getElementById("sentDetail");

  detail.innerHTML = `
    <div class="comm-alert-card report-detail-card">
      <div class="report-detail-header">
        <div>
          <h3>${escapeHtml(sentSubject(msg))}</h3>
          <small>From: Admin · To: ${escapeHtml(sentWorker(msg))} · ${formatTimestamp(reportTime(msg))}</small>
        </div>
        <button type="button" class="secondary-btn small-btn" onclick="backToSentInbox()">Back to Sent</button>
      </div>
      <div class="report-detail-body">
        <p class="report-field-label">To</p>
        <p class="report-desc">${escapeHtml(sentWorker(msg))}</p>
        <p class="report-field-label">Sensor ID</p>
        <p class="report-desc">${escapeHtml(sentSensor(msg))}</p>
        <p class="report-field-label">Message</p>
        <p class="report-desc">${escapeHtml(sentMessage(msg))}</p>
      </div>
    </div>
  `;

  container.classList.add("hidden");
  detail.classList.remove("hidden");
  updateSentTabLabel();
};

window.backToSentInbox = function() {
  const container = document.getElementById("sentList");
  const detail = document.getElementById("sentDetail");
  detail.classList.add("hidden");
  detail.innerHTML = "";
  container.classList.remove("hidden");
};

/* ---- Admin action: send a report/message to a worker ---- */

window.openNewTaskModal = function() {
  document.getElementById("newTaskModal").classList.remove("hidden");
};

window.closeNewTaskModal = function() {
  document.getElementById("newTaskModal").classList.add("hidden");
  document.getElementById("newTaskForm").reset();
};

window.createTask = function(event) {
  event.preventDefault();

  const worker = document.getElementById("taskWorker").value.trim();
  const sensorId = document.getElementById("taskSensor").value.trim();
  const subject = document.getElementById("taskTitle").value.trim();
  const message = document.getElementById("taskMessage").value.trim();

  if (!subject || !message) {
    alert("Please fill in both the subject and message.");
    return;
  }

  const now = Date.now();
  const newMsgRef = push(sentReportsRef);

  set(newMsgRef, {
    workerId: worker || "",
    sensorId: sensorId || "",
    subject: subject,
    message: message,
    timestamp: now
  })
    .then(() => {
      closeNewTaskModal();
      showToastMessage("Message sent to worker.");
    })
    .catch((error) => {
      alert("Failed to send message: " + error.message);
    });
};

/* ==================================================
   SENSOR DASHBOARD — monitoring only
   Data source: TANK_01/sensors (mobile-owned contract:
   { type, installedAt, lifespanDays, expiresAt, status, removedAt? }).
   Status mirrors the mobile app's computedStatus:
   ACTIVE (remaining > 7 days) | REPLACE (0 < remaining <= 7 days) |
   INACTIVE (removed or expired). Nothing is ever written back.
   ================================================== */

const REPLACE_THRESHOLD_DAYS = 7;
const REPLACEMENT_ALERT_DAYS = 7;

const sensorsRef = ref(db, `${ACTIVE_TANK}/sensors`);

onValue(sensorsRef, (snapshot) => {
  const data = snapshot.val();
  renderSensors(data);
  renderReplacementAlerts(data);
});

// Normalize an epoch value (seconds or ms) or date string to milliseconds.
function toEpochMs(value) {
  if (value === undefined || value === null || value === "") return NaN;
  if (typeof value === "number") {
    return String(value).length <= 10 ? value * 1000 : value;
  }
  const parsed = Date.parse(value);
  return isNaN(parsed) ? NaN : parsed;
}

function sensorRemainingDays(sensor) {
  // Mobile source of truth: expiresAt is an absolute epoch-ms timestamp.
  const expiresMs = toEpochMs(firstDefined(sensor.expiresAt, sensor.expires, sensor.expires_at));
  if (!isNaN(expiresMs)) {
    return Math.floor((expiresMs - Date.now()) / (1000 * 60 * 60 * 24));
  }

  const explicit = firstDefined(
    sensor.remainingDays, sensor.remainingLifespan,
    sensor.remainingLifespanDays, sensor.daysRemaining,
    sensor.remaining, sensor.remaining_days
  );
  if (explicit !== undefined) {
    const n = Number(explicit);
    if (!isNaN(n)) return n;
  }

  const lifespan = Number(firstDefined(sensor.lifespanDays, sensor.lifespan, sensor.lifespan_days));
  const installedMs = toEpochMs(firstDefined(sensor.installedDate, sensor.installedAt, sensor.installationDate, sensor.installed));

  if (isNaN(lifespan) || isNaN(installedMs)) return isNaN(lifespan) ? 0 : lifespan;

  const daysSince = Math.floor((Date.now() - installedMs) / (1000 * 60 * 60 * 24));
  return lifespan - daysSince;
}

// A sensor is detached once the mobile app stamps removedAt, or when a
// legacy attachment flag explicitly says so.
function sensorIsRemoved(sensor) {
  if (firstDefined(sensor.removedAt, sensor.removed, sensor.removed_at) !== undefined) return true;
  if (sensor.attached === false || sensor.isAttached === false) return true;
  const state = String(firstDefined(sensor.attachmentState, sensor.attachment, sensor.attachStatus) || "").toLowerCase();
  return state === "detached" || state === "off";
}

// Mirrors the mobile app's computedStatus:
// INACTIVE (removed or expired) > REPLACE (<= 7 days) > ACTIVE.
function sensorStatus(sensor) {
  const remaining = sensorRemainingDays(sensor);
  if (sensorIsRemoved(sensor) || remaining <= 0) return { label: "INACTIVE", tag: "danger" };
  if (remaining <= REPLACE_THRESHOLD_DAYS) return { label: "REPLACE", tag: "warning" };
  return { label: "ACTIVE", tag: "good" };
}

// "WL-01 · Water Level" when the mobile app supplied a sensor type.
function sensorLabel(id, sensor) {
  const type = firstDefined(sensor.type, sensor.sensorType, sensor.sensor_type);
  const name = firstDefined(sensor.sensorId, sensor.sensor, sensor.name) || id || "Unknown";
  return type ? `${name} · ${type}` : name;
}

function formatInstalledDate(installed) {
  if (!installed) return "-";
  const ms = toEpochMs(installed);
  if (isNaN(ms)) return String(installed);
  const d = new Date(ms);
  return isNaN(d.getTime()) ? String(installed) : d.toLocaleDateString();
}

function renderSensors(data) {
  const tbody = document.getElementById("sensorsTableBody");
  tbody.innerHTML = "";

  const emptyRow = `<tr><td colspan="5">No sensors found in TANK_01/sensors yet.</td></tr>`;

  if (!data) {
    tbody.innerHTML = emptyRow;
    return;
  }

  const entries = Object.entries(data);

  if (entries.length === 0) {
    tbody.innerHTML = emptyRow;
    return;
  }

  entries.forEach(([id, sensor]) => {
    const label = sensorLabel(id, sensor);
    const installed = formatInstalledDate(firstDefined(sensor.installedDate, sensor.installedAt, sensor.installationDate, sensor.installed));
    const remaining = sensorRemainingDays(sensor);
    const removed = sensorIsRemoved(sensor);
    const remainingText = `${Math.max(0, Math.floor(remaining))} days`;
    const status = sensorStatus(sensor);
    const attachText = removed ? "Detached" : "Attached";

    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${escapeHtml(label)}</td>
      <td>${escapeHtml(installed)}</td>
      <td>${remainingText}</td>
      <td>${attachText}</td>
      <td><span class="tag ${status.tag}">${status.label}</span></td>
    `;
    tbody.appendChild(tr);
  });
}

/* ---- Dashboard: sensor replacement alerts (within 7 days of replacement) ---- */

function renderReplacementAlerts(data) {
  const container = document.getElementById("replacementAlertsList");
  if (!container) return;

  if (!data) {
    container.innerHTML = `<p class="comm-empty">No sensor replacement alerts.</p>`;
    return;
  }

  const entries = Object.entries(data)
    .filter(([, sensor]) => !sensorIsRemoved(sensor))
    .map(([id, sensor]) => {
      const remaining = sensorRemainingDays(sensor);
      return {
        id,
        remaining,
        sensorId: sensorLabel(id, sensor),
        installed: formatInstalledDate(firstDefined(sensor.installedDate, sensor.installedAt, sensor.installationDate, sensor.installed))
      };
    })
    .filter((e) => e.remaining <= REPLACEMENT_ALERT_DAYS)
    .sort((a, b) => a.remaining - b.remaining);

  if (entries.length === 0) {
    container.innerHTML = `<p class="comm-empty">All sensors are within their healthy replacement window.</p>`;
    return;
  }

  container.innerHTML = entries.map((e) => {
    const remainingShown = Math.max(0, Math.ceil(e.remaining));
    const overdue = e.remaining <= 0;
    const daysText = overdue
      ? "Overdue for replacement"
      : `Replace within ${remainingShown} day${remainingShown === 1 ? "" : "s"}`;
    const border = overdue ? "danger-border" : "warning-border";

    return `
      <div class="alert-item ${border}">
        <strong>${escapeHtml(e.sensorId)} needs replacement</strong>
        <p>${daysText}. Installed: ${escapeHtml(e.installed)}</p>
        <small>Remaining lifespan: ${remainingShown} days</small>
      </div>
    `;
  }).join("");
}

/* ==================================================
   ALERT HISTORY — tank-scoped alerts
   Data source: TANK_01/alerts
   ================================================== */

const alertsRef = ref(db, `${ACTIVE_TANK}/alerts`);

let latestAlerts = null;
let activeAlertFilter = "all";

onValue(alertsRef, (snapshot) => {
  latestAlerts = snapshot.val();
  renderAlerts();
});

window.applyAlertFilter = function() {
  const select = document.getElementById("alertFilter");
  activeAlertFilter = select ? select.value : "all";
  renderAlerts();
};

function alertTime(alert) {
  const raw = firstDefined(alert.timestamp, alert.createdAt, alert.time);
  if (raw === undefined || raw === null || raw === "") return 0;
  if (typeof raw === "string") {
    const parsed = Date.parse(raw);
    return isNaN(parsed) ? 0 : parsed;
  }
  return Number(raw) || 0;
}

function alertParameter(alert) {
  const p = String(firstDefined(alert.parameter, alert.type, alert.category, alert.sensor) || "").toLowerCase();
  if (p.includes("temp")) return "temperature";
  if (p.includes("ph")) return "ph";
  if (p.includes("tds") || p.includes("salinity")) return "tds";
  if (p.includes("water") || p.includes("level")) return "waterlevel";
  return "other";
}

function alertSeverity(alert) {
  const s = String(firstDefined(alert.severity, alert.level, alert.status) || "").toLowerCase();
  if (s.includes("crit") || s.includes("danger") || s.includes("high")) return "danger";
  return "warning";
}

function renderAlerts() {
  const container = document.getElementById("alertList");
  if (!container) return;

  if (!latestAlerts) {
    container.innerHTML = `<p class="comm-empty">No alerts recorded yet.</p>`;
    return;
  }

  const entries = Object.entries(latestAlerts)
    .map(([id, alert]) => ({ id, alert }))
    .filter(({ alert }) => activeAlertFilter === "all" || alertParameter(alert) === activeAlertFilter)
    .sort((a, b) => alertTime(b.alert) - alertTime(a.alert));

  if (entries.length === 0) {
    container.innerHTML = `<p class="comm-empty">No alerts match the selected filter.</p>`;
    return;
  }

  container.innerHTML = entries.map(({ alert }) => {
    // Header: the raw parameter/sensor ID (e.g. "TDS_01"), falling back to a title.
    const header = firstDefined(alert.parameter, alert.sensor, alert.title, alert.name) || "Alert";
    // Body: the action taken / notes / description.
    const text = firstDefined(alert.actionTaken, alert.notes, alert.description, alert.text, alert.message, alert.title) || "";
    const hasValue = alert.value !== undefined && alert.value !== null && alert.value !== "";
    const severity = alertSeverity(alert);
    const severityLabel = String(firstDefined(alert.severity, alert.level, alert.status) || severity);
    // Prefer a stored display string (e.g. "10:30 PM"); otherwise format the timestamp.
    const timeText = typeof alert.time === "string"
      ? alert.time
      : formatTimestamp(alertTime(alert));
    const border = severity === "danger" ? "danger-border" : "warning-border";

    return `
      <div class="alert-item ${border}">
        <div class="alert-top">
          <strong>${escapeHtml(header)}</strong>
          <span class="tag ${severity === "danger" ? "danger" : "warning"}">${escapeHtml(severityLabel)}</span>
        </div>
        ${text ? `<p>${escapeHtml(text)}</p>` : ""}
        ${hasValue ? `<p>Value: <strong>${escapeHtml(alert.value)}</strong></p>` : ""}
        <small>${escapeHtml(timeText)}</small>
      </div>
    `;
  }).join("");
}

/* ==================================================
   MAIN DASHBOARD — current tank readings
   Data source: tank_status (single source of truth for
   the current pH / TDS / temperature / waterlevel /
   timestamp on the main dashboard).
   ================================================== */

const tankStatusRef = ref(db, "tank_status");

let latestTankStatus = null;

onValue(tankStatusRef, (snapshot) => {
  renderTankStatus(snapshot.val());
});

function extractStatusValues(obj) {
  return {
    temperature: firstDefined(obj.temperature, obj.temp),
    ph: firstDefined(obj.ph),
    tds: firstDefined(obj.tds),
    waterlevel: firstDefined(obj.waterlevel, obj.waterLevel),
    timestamp: firstDefined(obj.timestamp)
  };
}

// Fallback: if tank_status is empty, show the latest reading from the
// history node so the dashboard still displays Firebase data.
function latestReadingFromHistory() {
  const merged = latestReadings || {};
  const entries = Object.values(merged)
    .map((r) => normalizeReading(r))
    .filter((r) => r.timestamp > 0);
  if (entries.length === 0) return null;
  entries.sort((a, b) => a.timestamp - b.timestamp);
  return entries[entries.length - 1];
}

// Compare a parameter value against the configured thresholds and derive a
// KPI status label (OPTIMAL / WARNING / CRITICAL).
function thresholdStatus(param, value, t) {
  const v = Number(value);
  if (isNaN(v) || !t) return null;
  switch (param) {
    case "temperature":
      if (t.temp_critical_max !== undefined && v > Number(t.temp_critical_max)) return { label: "CRITICAL", severity: "danger" };
      if (v > Number(t.temp_max) || v < Number(t.temp_min)) return { label: "WARNING", severity: "warning" };
      return { label: "OPTIMAL", severity: "good" };
    case "ph":
      if (t.ph_critical_min !== undefined && v < Number(t.ph_critical_min)) return { label: "CRITICAL", severity: "danger" };
      if (v > Number(t.ph_max) || v < Number(t.ph_min)) return { label: "WARNING", severity: "warning" };
      return { label: "OPTIMAL", severity: "good" };
    case "tds":
      if (t.tds_critical_max !== undefined && v > Number(t.tds_critical_max)) return { label: "CRITICAL", severity: "danger" };
      if (v > Number(t.tds_max)) return { label: "WARNING", severity: "warning" };
      return { label: "OPTIMAL", severity: "good" };
    case "waterlevel":
      if (v < Number(t.waterlevel_min) || v > Number(t.waterlevel_max)) return { label: "CRITICAL", severity: "danger" };
      return { label: "OPTIMAL", severity: "good" };
  }
  return null;
}

function applyKpiTag(valueId, status) {
  const valueEl = document.getElementById(valueId);
  if (!valueEl) return;
  const card = valueEl.closest(".kpi-card");
  const tag = card ? card.querySelector(".tag") : null;
  if (!card || !tag) return;

  card.classList.remove("good-card", "warning-card", "danger-card");
  tag.classList.remove("good", "warning", "danger");

  if (!status) {
    tag.textContent = "-";
    return;
  }
  tag.classList.add(status.severity);
  tag.textContent = status.label;
}

function renderTankStatus(data) {
  latestTankStatus = data;

  const hasReal = data && Object.keys(data).length > 0;
  const raw = hasReal ? data : latestReadingFromHistory();
  const source = raw ? extractStatusValues(raw) : null;

  const setKpi = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.textContent = text;
  };
  const has = (v) => v !== undefined && v !== null && v !== "";

  if (!source) {
    setKpi("tempValue", "-");
    setKpi("phValue", "-");
    setKpi("tdsValue", "-");
    setKpi("levelValue", "-");
    applyKpiTag("tempValue", null);
    applyKpiTag("phValue", null);
    applyKpiTag("tdsValue", null);
    applyKpiTag("levelValue", null);
    updateHardwareStatus(0);
    return;
  }

  const temperature = source.temperature;
  const ph = source.ph;
  const tds = source.tds;
  const waterlevel = source.waterlevel;
  const ts = source.timestamp;

  setKpi("tempValue", has(temperature) ? `${temperature}°C` : "-");
  setKpi("phValue", has(ph) ? ph : "-");
  setKpi("tdsValue", has(tds) ? `${tds} ppm` : "-");
  setKpi("levelValue", has(waterlevel) ? `${waterlevel} %` : "-");

  const t = latestThresholds;
  applyKpiTag("tempValue", thresholdStatus("temperature", temperature, t));
  applyKpiTag("phValue", thresholdStatus("ph", ph, t));
  applyKpiTag("tdsValue", thresholdStatus("tds", tds, t));

  const wl = Number(waterlevel);
  if (has(waterlevel) && !isNaN(wl)) {
    updateWaterLevelStatus(wl);
  } else {
    applyKpiTag("levelValue", null);
  }

  updateHardwareStatus(ts);
}

/* ---- Alerts are READ-ONLY from the web ----
   The ESP32 is the sole producer of TANK_01/alerts. The web must never
   write alert entries: the Cloud Function fires an FCM push for every
   new alert node, so a web-generated alert would duplicate the device's
   push. Alert History below only reads the node. */

/* ==================================================
   LIVE READINGS — TANK_01/history (written by the ESP32)
   Feeds the trend/forecast charts and the predictor.
   Current KPI values on the main dashboard come from
   tank_status instead.
   ================================================== */

const historyRef = ref(db, `${ACTIVE_TANK}/history`);

let latestReadings = null;
let latestTdsSeries = [];

onValue(historyRef, (snapshot) => {
  latestReadings = snapshot.val();
  renderReadings(latestReadings);
  renderTankStatus(latestTankStatus);
});

function normalizeReading(r) {
  return {
    temp: Number(firstDefined(r.temp, r.temperature)),
    ph: Number(firstDefined(r.ph)),
    tds: Number(firstDefined(r.tds)),
    waterLevel: Number(firstDefined(r.waterLevel, r.waterlevel)),
    timestamp: Number(r.timestamp) || 0
  };
}

function avg(values) {
  const nums = values.filter((v) => !isNaN(v) && v !== null && v !== undefined);
  if (nums.length === 0) return 0;
  return nums.reduce((sum, v) => sum + v, 0) / nums.length;
}

function readingMs(ts) {
  return Number(ts) > 1e12 ? Number(ts) : Number(ts) * 1000;
}

function dailySeries(readings, days) {
  const series = { temp: [], ph: [], tds: [], waterLevel: [] };
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  for (let i = days - 1; i >= 0; i--) {
    const start = new Date(today);
    start.setDate(today.getDate() - i);
    const end = new Date(start);
    end.setDate(start.getDate() + 1);

    const dayReadings = readings.filter((r) => {
      const t = readingMs(r.timestamp);
      return t >= start.getTime() && t < end.getTime();
    });

    series.temp.push(Number(avg(dayReadings.map((r) => r.temp)).toFixed(1)));
    series.ph.push(Number(avg(dayReadings.map((r) => r.ph)).toFixed(2)));
    series.tds.push(Math.round(avg(dayReadings.map((r) => r.tds))));
    series.waterLevel.push(Number(avg(dayReadings.map((r) => r.waterLevel)).toFixed(1)));
  }

  return series;
}

function renderReadings(data) {
  const readings = [];

  if (data) {
    Object.entries(data).forEach(([id, r]) => {
      readings.push(normalizeReading(r));
    });
  }

  const sorted = readings
    .filter((r) => r.timestamp > 0)
    .sort((a, b) => a.timestamp - b.timestamp);

  const series = dailySeries(sorted, 7);

  latestTdsSeries = series.tds;

  drawOrUpdateChart("trendChart", "TDS / Salinity", series.tds, "#facc15");
  drawOrUpdateChart("tempChart", "Temperature", series.temp, "#38bdf8");
  drawOrUpdateChart("phChart", "pH Level", series.ph, "#22c55e");
  drawOrUpdateChart("tdsChart", "TDS", series.tds, "#facc15");

  const forecast = buildTdsForecast(series.tds);
  drawOrUpdateChart("forecastChart", "TDS Forecast", forecast.data, "#ef4444", forecast.labels);

  updatePredictor();
}

/* ---- Predictor: days until next water change (TDS trend) ---- */

function tdsTrend(history) {
  const valid = (history || []).map(Number);
  const n = valid.length;
  if (n < 2) return { slope: 0, current: valid[n - 1] || 0 };
  const xMean = (n - 1) / 2;
  const yMean = valid.reduce((s, v) => s + v, 0) / n;
  let num = 0, den = 0;
  for (let i = 0; i < n; i++) {
    num += (i - xMean) * (valid[i] - yMean);
    den += (i - xMean) * (i - xMean);
  }
  return { slope: den === 0 ? 0 : num / den, current: valid[n - 1] };
}

function updatePredictor() {
  const daysEl = document.getElementById("estimateDays");
  const tagEl = document.querySelector("#predictor .predictor-box .tag");
  if (!daysEl) return;

  const tdsMax = latestThresholds && !isNaN(Number(latestThresholds.tds_max)) ? Number(latestThresholds.tds_max) : 600;
  const { slope, current } = tdsTrend(latestTdsSeries);

  if (!latestTdsSeries.length || !latestTdsSeries.some((v) => Number(v) !== 0)) {
    daysEl.textContent = "—";
    if (tagEl) tagEl.textContent = "Awaiting TDS data...";
    return;
  }

  const days = slope > 0.01 ? (tdsMax - current) / slope : null;

  if (days === null || !isFinite(days) || days < 0) {
    daysEl.textContent = "—";
    if (tagEl) tagEl.textContent = "TDS stable — no change needed soon";
  } else if (days <= 1) {
    daysEl.textContent = "Today";
    if (tagEl) tagEl.textContent = "TDS near the limit — change water soon";
  } else {
    daysEl.textContent = `${Math.round(days)} Days`;
    if (tagEl) tagEl.textContent = `Based on increasing TDS trend (${slope.toFixed(1)} ppm/day)`;
  }
}

function buildTdsForecast(history) {
  const tdsMax = latestThresholds && !isNaN(Number(latestThresholds.tds_max)) ? Number(latestThresholds.tds_max) : 600;
  const labels = lastNDayLabels(7);
  const data = (history || []).map(Number);
  const n = data.length;
  if (n < 2) return { data, labels };

  const { slope, current } = tdsTrend(history);
  const today = new Date();
  const points = 5;
  for (let i = 1; i <= points; i++) {
    const d = new Date(today);
    d.setDate(today.getDate() + i);
    labels.push(d.toLocaleDateString(undefined, { month: "short", day: "numeric" }));
    data.push(slope > 0 ? Math.min(current + slope * i, tdsMax) : current + slope * i);
  }
  return { data, labels };
}

/* ---- Hardware status: ONLINE only while readings are fresh.
   The ESP32 writes every 15 s, so a 60 s window flags a dead device
   promptly without flickering on a single missed cycle. ---- */

const HARDWARE_STALE_MS = 60 * 1000;

function updateHardwareStatus(latestTimestamp) {
  const row = document.querySelector("#dashboard .hardware-row strong");
  if (!row) return;

  const online = latestTimestamp && (Date.now() - readingMs(latestTimestamp)) < HARDWARE_STALE_MS;

  if (online) {
    row.textContent = "ONLINE";
    row.className = "on";
  } else {
    row.textContent = "OFFLINE";
    row.className = "off";
  }
}

/* ---- Analytics: export readings as CSV ---- */

window.downloadCsv = function() {
  if (!latestReadings || Object.keys(latestReadings).length === 0) {
    alert("No readings available to export.");
    return;
  }

  const rows = [["timestamp", "temp", "ph", "tds", "waterLevel"]];
  Object.entries(latestReadings).forEach(([id, r]) => {
    const n = normalizeReading(r);
    rows.push([n.timestamp, n.temp, n.ph, n.tds, n.waterLevel]);
  });
  rows.sort((a, b) => Number(a[0]) - Number(b[0]));

  const csv = rows.map((row) => row.join(",")).join("\n");
  const blob = new Blob([csv], { type: "text/csv" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `TANK_01_readings_${new Date().toISOString().slice(0, 10)}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
};

/* ==================================================
   CHARTS
   ================================================== */

const chartOptions = {
  responsive: true,
  plugins: {
    legend: {
      labels: {
        color: "#e8f0fb"
      }
    }
  },
  scales: {
    x: {
      ticks: { color: "#8fa4bf" },
      grid: { color: "#223855" }
    },
    y: {
      ticks: { color: "#8fa4bf" },
      grid: { color: "#223855" }
    }
  }
};

function lastNDayLabels(n) {
  const labels = [];
  const today = new Date();
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(today);
    d.setDate(today.getDate() - i);
    labels.push(d.toLocaleDateString(undefined, { month: "short", day: "numeric" }));
  }
  return labels;
}

const chartInstances = {};

function drawOrUpdateChart(canvasId, label, data, borderColor, labels) {
  const ctx = document.getElementById(canvasId);

  if (!ctx) return;

  const hasData = Array.isArray(data) && data.some((v) => Number(v) !== 0);

  const card = ctx.closest(".card");
  let note = card ? card.querySelector(".chart-empty-note") : null;

  if (!hasData) {
    // No real readings yet — show an honest placeholder instead of a flat line.
    if (card) {
      if (!note) {
        note = document.createElement("p");
        note.className = "chart-empty-note";
        card.appendChild(note);
      }
      note.textContent = "No data available yet.";
    }
    ctx.style.display = "none";
    return;
  }

  if (note) note.remove();
  ctx.style.display = "";

  const chartLabels = labels || lastNDayLabels(7);

  // Update an existing chart instead of creating a second one.
  if (chartInstances[canvasId]) {
    const chart = chartInstances[canvasId];
    chart.data.labels = chartLabels;
    chart.data.datasets[0].data = data;
    chart.update();
    return;
  }

  chartInstances[canvasId] = new Chart(ctx, {
    type: "line",
    data: {
      labels: chartLabels,
      datasets: [{
        label: label,
        data: data,
        borderColor: borderColor,
        backgroundColor: "rgba(56, 189, 248, 0.12)",
        tension: 0.35,
        fill: true
      }]
    },
    options: chartOptions
  });
}

window.onload = function () {
  drawOrUpdateChart("trendChart", "TDS / Salinity", [], "#facc15");
  drawOrUpdateChart("tempChart", "Temperature", [], "#38bdf8");
  drawOrUpdateChart("phChart", "pH Level", [], "#22c55e");
  drawOrUpdateChart("tdsChart", "TDS", [], "#facc15");
  drawOrUpdateChart("forecastChart", "TDS Forecast", [], "#ef4444");
};