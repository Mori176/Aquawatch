/* ============================================================
   AquaWatch — Seed 7 days of chart history into TANK_01/history
   ------------------------------------------------------------
   Same output as the teammate's seedHistory() snippet, but using
   the modular Firebase SDK + the app's existing session so it
   actually runs in THIS app's console.
   HOW TO USE:
   1) Open the AquaWatch admin app and LOG IN.
   2) F12 -> Console -> paste this file -> Enter.
   The trend / forecast charts fill in with 7 days of realistic
   data immediately (336 readings, one every 30 minutes).
   ============================================================ */
(async () => {
  const { ref, update } = await import(
    "https://www.gstatic.com/firebasejs/10.12.2/firebase-database.js"
  );

  const db = window.db;
  if (!db) {
    console.error("window.db not found. Open the AquaWatch app in this tab first.");
    return;
  }

  const historyRef = ref(db, "TANK_01/history");
  const now = Date.now();
  const updates = {};

  // 336 points = 7 days, 30 minutes apart.
  for (let i = 336; i >= 1; i--) {
    const t = now - i * 30 * 60 * 1000;
    updates["r" + i] = {
      temperature: Number((28 + Math.sin(i / 8) * 1.5).toFixed(1)), // 26.5–29.5 °C
      ph: Number((7.5 + Math.sin(i / 12) * 0.3).toFixed(2)),         // 7.2–7.8
      tds: Math.round(450 + Math.sin(i / 20) * 40),                  // 410–490 ppm
      waterlevel: Number((43 + Math.sin(i / 30) * 8).toFixed(1)),    // ~35–51 %
      timestamp: t                                                   // milliseconds
    };
  }

  await update(historyRef, updates);
  console.log("Seeded " + Object.keys(updates).length + " readings into TANK_01/history.");
})().catch((err) => console.error("Seed failed:", err));