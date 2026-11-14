// Counts a download of Skillori and sends it on to Skillori.dmg in Dropbox. vercel.json routes
// skillori.app/download here, and every download button on the site points at that address, so
// the buttons never change when a new version ships: scripts/release.sh replaces the file in
// Dropbox under the same name, and Dropbox keeps its link.
//
// Only numbers are kept: a total and one per day (Stockholm time). Nothing about who downloaded,
// no address and no cookie. The numbers are in the Redis database (Upstash) under Storage in the
// Vercel project, shared with Lore, so Skillori's numbers are under their own key, skillori:dmg.
// Without the database, or when it doesn't answer in time, the download still goes on, uncounted.

// Written by `sh scripts/release.sh --link "<Dropbox link>"`, together with DMG_URL in
// scripts/release.conf. Empty until the first release is in Dropbox.
const DMG_URL = "https://dl.dropboxusercontent.com/scl/fi/5a712jyr61keg4ii1wszr/Skillori.dmg?rlkey=6mjshiwn0xvhkh8mfcdivcrwa&dl=1";

export async function GET() {
  if (!DMG_URL) return notYet();
  try {
    await count();
  } catch (e) {
    console.log(`[Skillori] download not counted: ${e}`);
  }
  return redirect(DMG_URL);
}

// Where the link goes, without counting, as scripts/release.sh checks it.
export function HEAD() {
  if (!DMG_URL) return notYet();
  return redirect(DMG_URL);
}

// One hash in Redis: total, and one field per day.
const KEY = "skillori:dmg";

async function count() {
  const base = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
  const token = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;
  if (!base || !token) return;
  const day = new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Stockholm" });
  const res = await fetch(`${base}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}` },
    body: JSON.stringify([["HINCRBY", KEY, "total", 1], ["HINCRBY", KEY, day, 1]]),
    signal: AbortSignal.timeout(2000),
  });
  if (!res.ok) throw new Error(`Redis answered ${res.status}`);
}

function redirect(to) {
  return new Response(null, { status: 302, headers: { Location: to, "Cache-Control": "no-store" } });
}

// Before the first release: back to the changelog, which says it's coming.
function notYet() {
  return new Response(null, { status: 302, headers: { Location: "/changelog/", "Cache-Control": "no-store" } });
}
