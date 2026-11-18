# Backlog

Prioriterad i ordning inom varje etapp. Etapperna följer [produktbriefen §14](Skillori-produktbrief.md). Det som är levererat markeras ✅. Uppdaterad 16 november 2026. Appen läser inventeringen, kontrollerar källor och kan köra uppdateringar via `npx skills`. Version 0.1.0 (första betan) släpptes 14 november och laddas ner från skillori.app, som nu indexeras av sökmotorer.

## Etapp 0 — Verifiera integrationskontrakt

- ✅ Lokal inventering av skill-rötter och pluginmetadata ([rapport](research/lokal-inventering-2026-11-11.md))
- ✅ Verifiera att `skillFolderHash` = git-trädhash = GitHubs katalog-SHA
- ✅ Kompatibilitetsmatris från officiell dokumentation ([matris](research/kompatibilitetsmatris.md))
- ✅ Arkitekturbeslut 0001–0005 (0005: produktnamnet Skillori)
- ✅ Tre första visuella riktningar ([sammanfattning](design/visuella-riktningar-2026-11-11.md)). Underkända av produktägaren: når inte önskad nivå.
- ✅ Designbaseline från Mobbin ([baseline](design/mobbin-baseline-2026-11-11.md))
- ✅ Karaktärskälla: produktägaren lutar mest mot **instrument/precision** (2026-11-11, se [baseline §1](design/mobbin-baseline-2026-11-11.md))
- ✅ UI-grund utredd: native SwiftUI/AppKit med eget komponentlager `SkilloriUI` ([rapport](design/ui-bibliotek-utforskning.md))
- ✅ Visuell riktning Readout, omgång 1–4 ([riktning](design/visuell-riktning-readout-2026-11-12.md)). Den 14 november ersattes de platta accenterna av ljusblock (`LightField`, Spectral och Bloom), som produktägaren godkände.
- ✅ `skillori.app` är registrerad. DNS ligger hos GoDaddy och sajten på Vercel. Kvar: kontrollera varumärkesregister (produktägaren).
- ✅ **Teknisk spike**: menyradsapp, discovery mot riktiga rötter, signering och notarisering ([rapport](research/spike-2026-11-11.md)). Kvar: TCC för `~/Documents`, Claude Desktop-rötter, manuell kontroll av panelen.
- ✅ Grundläggande fixtures i tester (symlänkar, kopior, plugin-cache, föräldralös version, marketplace-klon, trasig länk, lockfil). Kvar: nästlade projektrötter, fler varianter av trasig front matter, symlänkloopar, fientliga fixtures (traversal, specialfiler).
- [ ] Läs `npx skills`-källkoden: exakt mappning agent → katalog för alla 15+ agenter, lockfilens schema per version.

## Etapp 1 — Läsande inventering

1. ✅ `SkilloriCore`: `SKILL.md`-parser (frontmatter, tolerant mot fel, ingen exekvering, högst 256 kB läses).
2. ✅ Git-trädhash i Swift + fil-manifest (testat mot `git write-tree` på fixtures).
3. Discovery-motor: rötter från adapterregler, gränser för djup/filer/storlek, symlänkupplösning med loopdetektion, fysisk deduplicering, undantag. **Delvis ✅:** rötter från adapterregler, symlänkupplösning och fysisk deduplicering. Kvar: gränser, loopdetektion, undantag.
4. ✅ Adapterregler v1: Claude Code, delad `~/.agents`, Cursor, Codex, Gemini CLI, OpenCode, Kiro och GitHub Copilot, samt Antigravity, Amp, Factory Droid, Devin och goose.
5. ✅ Proveniensadapter: `npx skills`-lockfil → källa + baseline-hash, `matchesBaseline`/`modified` lokalt.
6. Proveniensadaptrar läsande: Claude Code `installed_plugins.json`, Cursor plugin-cache, Codex `config.toml` → "Managed by …". **Delvis ✅:** "Managed by …" sätts i dag utifrån vilken rot en skill ligger i (plugin-cache, claude.ai, Cursor). Kvar: läsa `installed_plugins.json` och `config.toml`.
7. ✅ **Gruppera på distributionsenhet** (plugin) och visa egna skills först. Hanterat innehåll är 90 % av alla installationer (spikfynd 2). Biblioteket är ett träd med egna skills först och sedan "Managed by apps".
8. Begränsa agentmärken till agenter som finns installerade (spikfynd 3). Läs Codex `config.toml` för aktiverade plugins (spikfynd 4). **Delvis ✅ (16 november):** en skill visar bara agenter som har en app eller en inställningsmapp på datorn. Detaljvyn nämner de övriga som "Also read by …, if installed". ✅ Codex `config.toml` läses för `enabled` per plugin (16 november).
9. ✅ Markera "same name, different copy" med innehållsjämförelse (spikfynd 5). Klart 16 november: egna skills med samma namn hashas, och biblioteket skiljer "identical copies" från "versions". Panelen säger till när samma namn finns i olika versioner.
10. ✅ UI: menyradspanel (sammanfattning, senaste inventering), biblioteksfönster med sök/filter, detaljvy (sökväg, alias, agentkopplingar, källa, evidens), "Reveal in Finder", Coverage-vy (heter "Folders" i appen). **17 november:** biblioteket är omgjort ([omtag 2](design/plugin-uppdateringar-plan-2026-11-16.md)). Överst står det som behöver dig, med en mening och en knapp per sak. Under det finns två vägar in, dina skills och appernas. Detaljerna ligger på en sida per skill och en per app.
11. Inställningar: projektmappar, egna rötter, undantag. **Delvis ✅:** projektmappar, plus ett kort för appuppdateringar. Kvar: egna rötter, undantag.
12. ✅ Filbevakning (FSEvents) med debounce och periodisk avstämning. Klart 16 november: FSEvents bevakar mapparna med skills och lockfilens mapp, och appen läser om var 30:e minut och efter vila.

## Etapp 2 — Bevakning, diff och notiser (första kompletta MVP)

1. GitHub-källadapter: katalog-SHA via REST, ETag-cache, rate limit/backoff, offline/stale-status. **Delvis ✅ (13 november):** en fråga per källa utan konto (`UpstreamCheck.swift`), svar "not found", "asked to wait" och "no contact" hålls isär, och ett gammalt svar behålls med sitt eget datum när källan inte svarar. **✅ 16 november:** frågor skickas med ETag (ett 304-svar räknas inte mot gränsen), högst fyra går samtidigt, och appen väntar den tid GitHub anger efter en rate limit. Kvar: token för privata källor.
2. Uppdateringskontroll för lockfil-skills (R vs B) och plugin-commit-SHA:er där möjligt. **✅ för lockfil-skills (13 november):** statusarna Up to date, Update available, Held back, Changed here, Can't check, Not checked, No source och Managed visas i bibliotek, detaljvy, panel och menyikon. "Hold back" och "Release" finns, liksom "Copy update command" (`npx skills update <namn>`). Kontrollen är avstängd tills användaren slår på den, enligt briefen §5. **✅ Claude Code-plugins (16 november):** jämförs per plugin mot marketplacen, mappvis mot den installerade commiten eller mot marketplacens låsta commit, och visas som "Plugin update". **✅ Cursor och Codex (16 november):** varje plugin jämförs med versionen i sitt manifest i källans repo, där källan är git-utcheckningens fjärradress (Cursor) eller manifestets `repository`. Codex lokala marketplaces följer med Codex och frågas inte. Codex `config.toml` läses för vilka plugins som är påslagna. **Omtag (18 november):** Cursor och Codex har ingen uppdateringsknapp för plugins: Cursor skickar ut sina plugins från sin server, och `codex plugin` saknar `update`. En nyare version i källan står därför som information på appens sida ("Newer at source"), inte i listan över det som behöver dig. Skillori frågar Codex själv (`codex plugin list --json`, verktyget i ChatGPT.app eller `codex` i skalet) vilka plugins Codex läser. Mappar som Codex lämnat kvar efter bytet av katalog (`openai-curated` → `openai-curated-remote`) får statusen "Not read". Finns pluginen i den nya katalogen får raden en "Open in Codex"-knapp, som öppnar `codex://plugins/<id>`. Där lägger man till pluginen och loggar in. Plugins från Codex fjärrkatalog jämförs inte längre mot GitHub. En knapp som bara leder till sidan man redan står på visas inte.
3. "Link source…" för okända skills: repo-URL, underkatalog, ref/policy. Försök innehållsmatchning mot historik. **Delvis ✅ (13 november):** dialogen tar `owner/repo` eller en GitHub-adress, också till en mapp. Appen rangordnar källans skill-mappar: samma innehåll, samma namn, övriga. En länkad skill får status Up to date eller Differs from source, kan hållas tillbaka och kan länkas av. Länkar sparas i `sources.json`. Kvar: matchning mot källans historik, så att "differs" kan bli "äldre version" eller "ändrad här"; andra källor än GitHub; grenar med snedstreck i namnet.
4. Diffvy (filnivå + textdiff, markering av scripts/exekveringsbit). **Delvis ✅ (16 november):** detaljvyn listar tillagda, ändrade och borttagna filer utifrån fil-id:n, med körbara filer först. Kvar: textdiff.
5. SQLite/GRDB-lagring: policy, kandidater, notishistorik, check runs. Tills vidare ligger källsvar och "held back" i en JSON-fil (`~/Library/Application Support/Skillori/sources.json`).
6. Schemaläggning (var 6:e timme, paus, efter sömn), deduplicerade notiser, sekretessläge. **Delvis ✅:** var 6:e timme medan appen körs och vid "Check now". **✅ 16 november:** notiser för nya uppdateringar (en per kontroll, aldrig samma revision två gånger) och för körningar som slutar när inget fönster är framme. Appen kontrollerar efter sömn, och visar "No contact" när källorna inte svarar. Kvar: paus, sekretessläge.
7. Sparkle + DMG-pipeline + promosida (kan gå parallellt). **✅ byggt (14 november):** Sparkle 2.10.1 med egen användardriver, feed på `skillori.app/appcast.xml` och publik nyckel i `project.yml`. `scripts/release.sh` sköter version, bygge, notarisering, DMG, Dropbox, changelog och appcast. Sajten skillori.app har `/download` med nedladdningsräknare och `/changelog/`. Koncept B ("Three lights") är valt för promosidan, och detaljerna godkändes 15 november. ✅ Release 0.1.0 är notariserad och ligger i Dropbox, appcast och changelog är publicerade, och `noindex` är borttaget (14 november). Sajten har också sitemap och `robots.txt` (sitemapen byggs om av `release.sh`), share-bild (`site/og.jpg`) med og-taggar, och README beskriver release, nedladdningar och sitemap. Kvar: backup av den privata Sparkle-nyckeln, och att prova hela uppdateringsflödet i appen när nästa version finns.

## Publikt repo

- ✅ MIT-licens, README på engelska, CONTRIBUTING, SECURITY, dokumentindex och en GitHub Action som kör kärntesterna (14 november).
- ✅ Signeringen fungerar utan Apple-konto: ad hoc som standard, Developer ID läses från `Config/Signing.local.xcconfig`.
- ✅ Repot är publikt sedan 14 november, med historiken som den var. Kvar: `icomoon.ttf` saknar licenstext; lägg till en om produktägaren har en.
- ✅ Beskrivning, webbplats och topics på GitHub (14 november).
- ✅ Private vulnerability reporting är påslaget och social förhandsbild uppladdad. Sajten har GitHub-knappar i stället för "What's new", versionsetiketten länkar till changelogen och startsidans footer har raden "made with ♥" (14 november).

## Kvar efter 0.1.0

Att göra (produktägaren):
- [ ] Flytta den privata Sparkle-nyckeln från `~/skillori-sparkle-private-key` till en lösenordshanterare eller krypterad volym, och radera filen. Det är den enda kopian.

Att prova:
- [ ] Hela uppdateringsflödet i appen: en installerad 0.1.0 ska hitta och installera 0.1.1.
- [ ] Sitemap-steget i `release.sh` i en riktig release (det är bara provat på en kopia av sajten).
- [ ] En riktig `npx skills update` via körknappen.
- [ ] Klickflödet för Link source.
- ✅ Att ändra bibliotekets storlek (15 november): fungerar, och fönstret stannar nu vid 900×520 när man drar det mindre (det krympte förbi gränsen i 0.1.0).

Beslut:
- ✅ Sparkles standardval (15 november): den dagliga kontrollen är påslagen från start och kan stängas av i inställningarna; Install startar om appen direkt. Inget ändras i koden.
- ✅ Påståendet "no tracking" (15 november): står kvar, eftersom appen inte har identifierare, cookies eller analys och räknaren bara sparar siffror. Privacy-rutan, footern och README nämner nu den dagliga frågan till skillori.app och räknaren.
- ✅ Detaljerna i promosidans koncept B (15 november): Orchid-rutan, texterna under rutorna, trädkortet och åtgärdsfältet behålls som de är.
- ✅ Panelens skillrad (15 november): visar bara den nya revisionen (`→ 6a0393c`), så att platsen går till namnet. Gammal → ny finns i biblioteket.

## Etapp 3 — Begränsade säkra uppdateringar

**Påbörjat 13 november, på produktägarens begäran:** uppdateringen kan köras från appen. Kommandot visas i en kodruta med körknapp (panelen, detaljvyn) och som knappen "Update" i bibliotekets fasta rad. Appen startar `npx --yes skills update <namn> -g -y` genom användarens inloggningsskal, visar utskriften, och läser sedan om datorn och frågar källan igen. Det är installationsverktyget som skriver filerna; Skillori gör det inte själv. Namn skickas som argument, aldrig som skalsträng, och bara enkla mappnamn godtas. Inte provat mot en riktig uppdatering av den som byggde det. Kvar: backup och återställning, och uppdatering av skills som är länkade för hand. **16 november:** versionen av verktyget är fäst (`skills@1.7.6`), körningen kan stoppas, och ett hängande skal kan inte längre stoppa bakgrundskontrollerna.

Enligt briefen §10. Första kandidat: skills som ägs av `npx skills`. Antingen delegera till `npx skills update`, vilket kräver capability-verifiering och Node, eller ersätta katalogen själva med transaktion, backup och rollback.

## Senare / idéer

- "Find more…": sök `SKILL.md` i vald katalog och föreslå nya rötter.
- Fler marketplaces (skills.sh-katalog, Claude Desktop-plugins).
- Visa vilka agenter en skill *saknas* i ("Install for Codex too?"), endast som information.
- Export/import av bevakningskonfiguration.
