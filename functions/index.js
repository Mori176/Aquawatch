/**
 * AquaWatch Cloud Functions
 *
 * The "mailman": watches TANK_01/alerts and pushes every new alert
 * to all registered worker devices via Firebase Cloud Messaging.
 *
 * Deploy:
 *   firebase login
 *   firebase deploy --only functions --project myfishapp-4e3e6
 */
const { onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onAlertCreated = onValueCreated(
  {
    ref: "/TANK_01/alerts/{alertId}",
    region: "asia-southeast1", // same region as the RTDB
  },
  async (event) => {
    const alert = event.data.val();
    if (!alert) return null;

    const parameter = alert.parameter ?? "Tank";
    const severity = String(alert.severity ?? "warning").toUpperCase();
    const title = severity === "CRITICAL" ? "🔴 AquaWatch Critical" : "🟡 AquaWatch Alert";
    const body = alert.actionTaken
      ? `${parameter} — ${alert.actionTaken}`
      : `${parameter} needs attention`;

    // 1. Collect every registered worker device token.
    const usersSnap = await admin.database().ref("users").once("value");
    const tokens = [];
    const tokenOwner = {}; // token -> uid (for dead-token cleanup)
    usersSnap.forEach((child) => {
      const token = child.child("fcmToken").val();
      if (token) {
        tokens.push(token);
        tokenOwner[token] = child.key;
      }
    });

    if (tokens.length === 0) {
      console.log("No device tokens registered — nothing to push.");
      return null;
    }

    // 2. Push to every device in one multicast call.
    const message = {
      notification: { title, body },
      data: {
        severity,
        parameter: String(parameter),
        alertId: event.params.alertId,
      },
      android: { priority: "high" },
      tokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `Alert pushed to ${response.successCount}/${tokens.length} device(s).`
    );

    // 3. Clean up dead tokens (uninstalled apps) so they never get retried.
    const deadTokens = [];
    response.responses.forEach((r, i) => {
      if (!r.success) {
        console.error(`Push failed for ${tokens[i]}: ${r.error?.message}`);
        const code = r.error?.code ?? "";
        if (
          code.includes("registration-token-not-registered") ||
          code.includes("invalid-registration-token")
        ) {
          deadTokens.push(tokens[i]);
        }
      }
    });
    await Promise.all(
      deadTokens.map((t) =>
        admin.database().ref(`users/${tokenOwner[t]}/fcmToken`).remove()
      )
    );

    return null;
  }
);
