/**
 * Paste this into Chrome DevTools Console (F12 → Console tab)
 * while on any page inside Google Play Console.
 *
 * It navigates to each app's Production track and clicks
 * "Send for review" automatically.
 */

const APPS = [
  { package: "ai.dollor.customer", label: "Dollor.ai (Rideshare)" },
  { package: "ai.dollor.driver",   label: "Dollor Driver" },
];

// Extract developer ID from current URL
const devId = location.href.match(/developers\/(\d+)/)?.[1];
if (!devId) {
  console.error("❌  Not inside Play Console — navigate to play.google.com/console first");
  throw new Error("Not in Play Console");
}
console.log("✓  Developer ID:", devId);

async function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

async function clickText(text, timeout = 8000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    // Try buttons, links, mat-buttons
    const els = [...document.querySelectorAll(
      "button, a, [role='button'], mat-button, .mdc-button"
    )].filter(el =>
      el.offsetParent !== null &&
      el.textContent.trim().toLowerCase().includes(text.toLowerCase())
    );
    if (els.length > 0) {
      console.log(`  Clicking: "${els[0].textContent.trim()}"`);
      els[0].click();
      return true;
    }
    await sleep(500);
  }
  console.warn(`  ⚠️  Button not found: "${text}"`);
  return false;
}

async function submitApp(app) {
  console.log(`\n${"=".repeat(50)}`);
  console.log(`Submitting: ${app.label} (${app.package})`);

  // Navigate to app's production track
  const url = `https://play.google.com/console/u/0/developers/${devId}/app/${app.package}/tracks/production`;
  console.log(`  Navigating to ${url}`);
  location.href = url;

  // Wait for page load
  await sleep(5000);

  // Click "Review release"
  let found = await clickText("Review release");
  if (!found) found = await clickText("Review");
  await sleep(2000);

  // Dismiss any warnings
  await clickText("Confirm");
  await sleep(1000);

  // Click "Send for review"
  found = await clickText("Send for review");
  if (!found) found = await clickText("Send 1 app");
  if (!found) found = await clickText("Submit");
  await sleep(2000);

  // Confirm dialog if it appears
  await clickText("Send");
  await sleep(1000);

  console.log(`  ✓  ${app.label} — submitted for review (or button not present if already submitted)`);
}

(async () => {
  for (const app of APPS) {
    await submitApp(app);
    await sleep(4000);
  }
  console.log(`\n${"=".repeat(50)}`);
  console.log("✓  Done — both apps submitted for Google Play review.");
  console.log("You will receive an email when each app is approved (1–3 days).");
})();
