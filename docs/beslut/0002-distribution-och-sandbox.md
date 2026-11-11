# 0002 — Distribution utanför App Store, utan sandbox

**Status:** Accepterat · 2026-11-11 (bekräftat i [spike](../research/spike-2026-11-11.md))

## Kontext

Appen ska kunna laddas ned av andra från en promosida och installeras utan krångel. App Store är inget krav. Produktägaren har ett Apple Developer-konto med Developer ID.

Skillori behöver läsa många dolda kataloger i hemkatalogen (`~/.claude`, `~/.agents`, `~/.cursor`, `~/.codex`, `~/.gemini`, `~/.config/…`, `~/Library/Application Support/Claude`) och följa symlänkar mellan dem.

## Beslut

- **Developer ID-signering + notarisering + hardened runtime.** Leverans som `.dmg` (dra till Applications).
- **Ingen App Sandbox** i första versionerna.
- **Appuppdateringar via Sparkle** (EdDSA-signerade uppdateringar, appcast på promosidan). Sparkle är de facto-standard för appar utanför App Store. Detta är separat från skilluppdateringar.
- Projektmappar väljs med `NSOpenPanel`. Vi sparar sökvägen och, där macOS kräver det, en bookmark.

## Skäl

En sandlådad app kan inte läsa `~/.claude` m.fl. utan att användaren väljer varje dold katalog manuellt i en filväljare. Det är dålig UX och skör (symlänkar pekar ofta till andra rötter). Sandbox krävs bara för App Store. Utan sandbox gäller fortfarande macOS integritetsskydd (TCC) för t.ex. Skrivbord, Dokument, Hämtade filer och iCloud Drive. Projekt som ligger där kan ge en engångsfråga från systemet, vilket är acceptabelt och förväntat.

## Konsekvenser

- Vi tar själva ansvar för minsta möjliga åtkomst: appen läser bara kända och valda rötter (se 0001) och skriver bara i sin egen Application Support-katalog tills skrivstöd införs (etapp 3).
- App Store kan prövas senare, men kräver då en annan åtkomstmodell. Det är inte ett mål nu.
- Att verifiera i spike: att notarisering fungerar med kontot, att läsning av `~/Library/Application Support/Claude` inte ger TCC-dialog, beteende för projektmappar i `~/Documents`.
