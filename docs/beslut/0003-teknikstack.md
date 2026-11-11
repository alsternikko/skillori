# 0003 — Teknikstack och lägsta macOS-version

**Status:** Accepterat · 2026-11-11 (bekräftat i [spike](../research/spike-2026-11-11.md))

## Beslut

- **Språk/UI:** Swift 6 (strikt samtidighetskontroll), SwiftUI med `MenuBarExtra` (`.window`-stil för panelen) och separata `Window`/`Settings`-scener för bibliotek och inställningar. AppKit endast där SwiftUI inte räcker (t.ex. aktiveringspolicy, fokus för menyradsfönster).
- **Lägsta macOS:** **15 (Sequoia)** som utgångspunkt. Det täcker de flesta aktiva Mac-användare och ger moderna SwiftUI-API:er (`@Observable`, förbättrad `MenuBarExtra`). Kan höjas till 26 om spiken visar att något centralt kräver det. Byggs med Xcode 27.2.
- **Struktur:** Xcode-app-target + lokalt Swift-paket (`SkillwatchCore`) för all logik (discovery, hashing, proveniens, källor). Kärnan har inga UI-beroenden och testas med `swift test` och fixtures. UI-target blir tunn.
- **Lagring:** Etapp 1 klarar sig med en versionerad JSON-cache i Application Support (inventeringen kan alltid byggas om från disk). Från etapp 2, när bevakningspolicy, notishistorik och kandidater måste överleva omstart med transaktioner, införs **SQLite via GRDB**. Valet görs bakom ett protokoll så att det kan ändras. SwiftData väljs bort: svagare kontroll över migrationer och transaktioner, vilket briefen kräver.
- **Nätverk:** `URLSession` direkt mot GitHub REST API (ingen `git`-binär, ingen `gh`). ETag/villkorliga anrop och cache från början. Valfri GitHub-token i Keychain för högre rate limit och privata repon (etapp 3).
- **Innehållshash:** se [0004](0004-innehallshash-git-trad.md).

## Skäl

En liten bakgrundsapp som ska kännas native, dra lite energi och integrera med menyrad, notiser och Finder. SwiftUI räcker för panel och listor. Att lägga logiken i ett separat paket gör den testbar utan UI och utan att röra användarens riktiga skills.
