# Backlog

Prioriterad i ordning inom varje etapp. Etapperna följer [produktbriefen §14](Skillwatch-produktbrief.md). Det som är levererat markeras ✅. Spike-versionen av appen finns. Den är läsande och visar inventering, källa och lokal status.

## Etapp 0 — Verifiera integrationskontrakt

- ✅ Lokal inventering av skill-rötter och pluginmetadata ([rapport](research/lokal-inventering-2026-11-11.md))
- ✅ Verifiera att `skillFolderHash` = git-trädhash = GitHubs katalog-SHA
- ✅ Kompatibilitetsmatris från officiell dokumentation ([matris](research/kompatibilitetsmatris.md))
- ✅ Arkitekturbeslut 0001–0005 (0005: produktnamnet Skillori)
- ✅ Tre första visuella riktningar ([sammanfattning](design/visuella-riktningar-2026-11-11.md)). Underkända av produktägaren: når inte önskad nivå.
- ✅ Designbaseline från Mobbin ([baseline](design/mobbin-baseline-2026-11-11.md))
- ✅ Karaktärskälla: produktägaren lutar mest mot **instrument/precision** (2026-11-11, se [baseline §1](design/mobbin-baseline-2026-11-11.md))
- ✅ UI-grund utredd: native SwiftUI/AppKit med eget komponentlager `SkilloriUI` ([rapport](design/ui-bibliotek-utforskning.md))
- [ ] Produktägaren samlar visuella referenser med inriktning instrument/precision; därefter ny visuell riktning
- [ ] Registrera `skillori.app` och kontrollera varumärkesregister (produktägaren)
- ✅ **Teknisk spike**: menyradsapp, discovery mot riktiga rötter, signering och notarisering ([rapport](research/spike-2026-11-11.md)). Kvar: TCC för `~/Documents`, Claude Desktop-rötter, manuell kontroll av panelen.
- ✅ Grundläggande fixtures i tester (symlänkar, kopior, plugin-cache, föräldralös version, marketplace-klon, trasig länk, lockfil). Kvar: nästlade projektrötter, fler varianter av trasig front matter, symlänkloopar, fientliga fixtures (traversal, specialfiler).
- [ ] Läs `npx skills`-källkoden: exakt mappning agent → katalog för alla 15+ agenter, lockfilens schema per version.

## Etapp 1 — Läsande inventering

1. `SkilloriCore`: `SKILL.md`-parser (frontmatter, tolerant mot fel, ingen exekvering).
2. Git-trädhash i Swift + fil-manifest (testat mot `git write-tree` på fixtures).
3. Discovery-motor: rötter från adapterregler, gränser för djup/filer/storlek, symlänkupplösning med loopdetektion, fysisk deduplicering, undantag.
4. Adapterregler v1: Claude Code, delad `~/.agents`, Cursor, Codex, Gemini CLI, OpenCode, Kiro, GitHub Copilot.
5. Proveniensadapter: `npx skills`-lockfil → källa + baseline-hash, `matchesBaseline`/`modified` lokalt.
6. Proveniensadaptrar läsande: Claude Code `installed_plugins.json`, Cursor plugin-cache, Codex `config.toml` → "Managed by …".
7. **Gruppera på distributionsenhet** (plugin) och visa egna skills först. Hanterat innehåll är 90 % av alla installationer (spikfynd 2).
8. Begränsa agentmärken till agenter som finns installerade (spikfynd 3). Läs Codex `config.toml` för aktiverade plugins (spikfynd 4).
9. Markera "same name, different copy" med innehållsjämförelse (spikfynd 5).
10. UI: menyradspanel (sammanfattning, senaste inventering), biblioteksfönster med sök/filter, detaljvy (sökväg, alias, agentkopplingar, källa, evidens), "Reveal in Finder", Coverage-vy.
11. Inställningar: projektmappar, egna rötter, undantag.
12. Filbevakning (FSEvents) med debounce + periodisk avstämning.

## Etapp 2 — Bevakning, diff och notiser (första kompletta MVP)

1. GitHub-källadapter: katalog-SHA via REST, ETag-cache, rate limit/backoff, offline/stale-status. **Delvis ✅ (13 november):** en fråga per källa utan konto (`UpstreamCheck.swift`), svar "not found", "asked to wait" och "no contact" hålls isär, och ett gammalt svar behålls med sitt eget datum när källan inte svarar. Kvar: ETag-cache (ett prov gav fullt svar i stället för "oförändrat"), backoff efter rate limit, token för privata källor.
2. Uppdateringskontroll för lockfil-skills (R vs B) och plugin-commit-SHA:er där möjligt. **✅ för lockfil-skills (13 november):** statusarna Up to date, Update available, Held back, Changed here, Can't check, Not checked, No source och Managed visas i bibliotek, detaljvy, panel och menyikon. "Hold back" och "Release" finns, liksom "Copy update command" (`npx skills update <namn>`). Kontrollen är avstängd tills användaren slår på den, enligt briefen §5. Kvar: plugins, och att bekräfta att kommandot träffar den globala installationen utan `-g`.
3. "Link source…" för okända skills: repo-URL, underkatalog, ref/policy. Försök innehållsmatchning mot historik. **Delvis ✅ (13 november):** dialogen tar `owner/repo` eller en GitHub-adress, också till en mapp. Appen rangordnar källans skill-mappar: samma innehåll, samma namn, övriga. En länkad skill får status Up to date eller Differs from source, kan hållas tillbaka och kan länkas av. Länkar sparas i `sources.json`. Kvar: matchning mot källans historik, så att "differs" kan bli "äldre version" eller "ändrad här"; andra källor än GitHub; grenar med snedstreck i namnet.
4. Diffvy (filnivå + textdiff, markering av scripts/exekveringsbit).
5. SQLite/GRDB-lagring: policy, kandidater, notishistorik, check runs. Tills vidare ligger källsvar och "held back" i en JSON-fil (`~/Library/Application Support/Skillori/sources.json`).
6. Schemaläggning (var 6:e timme, paus, efter sömn), deduplicerade notiser, sekretessläge. **Delvis ✅:** var 6:e timme medan appen körs och vid "Check now". Kvar: notiser, paus, kontroll efter sömn.
7. Sparkle + DMG-pipeline + promosida (kan gå parallellt).

## Etapp 3 — Begränsade säkra uppdateringar

Enligt briefen §10. Första kandidat: skills som ägs av `npx skills`. Antingen delegera till `npx skills update`, vilket kräver capability-verifiering och Node, eller ersätta katalogen själva med transaktion, backup och rollback.

## Senare / idéer

- "Find more…": sök `SKILL.md` i vald katalog och föreslå nya rötter.
- Fler marketplaces (skills.sh-katalog, Claude Desktop-plugins).
- Visa vilka agenter en skill *saknas* i ("Install for Codex too?"), endast som information.
- Export/import av bevakningskonfiguration.
