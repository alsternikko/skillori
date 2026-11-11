# 0004 — Git-trädhash som innehållsidentitet

**Status:** Accepterat · 2026-11-11

## Kontext

Briefen föreslår ett eget deterministiskt manifest-hash. Lokal inventering visade att `npx skills` sparar `skillFolderHash`, och den är **exakt git-trädhashen** för skillkatalogen. Den är också identisk med den katalog-SHA som GitHubs API returnerar för samma sökväg (verifierat för tre skills, se [lokal inventering §4](../research/lokal-inventering-2026-11-11.md)). Plugin-system (Claude Code, Cursor) använder commit-SHA:er.

## Beslut

Skillwatch använder **git-trädhashen (SHA-1-objektformat)** för en skillkatalog som primär innehållsidentitet och implementerar den i ren Swift:

- blob: `sha1("blob <len>\0" + bytes)`
- tree: poster sorterade enligt git-regler, `"<mode> <name>\0" + rå 20-byte-hash`, mode `100644`, `100755`, `120000` (symlänk, hash av länkmålets text) eller `40000`.

Utöver hashen sparas ett fil-manifest (relativ sökväg, läge, storlek, blob-hash) så att diff och "vilka filer ändrades" kan visas utan att hämta om allt.

## Skäl

- Vi kan jämföra lokalt innehåll med lockfiler och med GitHub **utan att hämta filer**: ett API-anrop per källkatalog räcker för att avgöra om något ändrats.
- Ändringar utanför skillkatalogen påverkar inte hashen. Det uppfyller kravet "ny commit i repot ≠ ny skillversion".
- Ingen `git`-binär körs, så inga hooks, filter eller konfigurationer kan köra kod (säkerhetskrav i briefen §11).

## Avgränsningar

- Git ignorerar tomma kataloger och tidsstämplar, och lagrar endast körbar-biten av rättigheterna. Det matchar briefens krav.
- Filer som är `.gitignore`-rade upstream men finns lokalt ger skillnad. Det visas som lokal ändring med fillista, vilket är korrekt beteende.
- SHA-1 är inte kollisionssäkert mot aktiv attack. Hashen används för *identitet och förändringsdetektion*, inte som säkerhetsintyg (i linje med briefens "Verified source ≠ ofarlig"). Repos i SHA-256-format stöds inte förrän de dyker upp i praktiken.
