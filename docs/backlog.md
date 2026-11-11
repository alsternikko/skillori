# Backlog

Prioriterad i ordning inom varje etapp. Etapperna följer [produktbriefen §14](Skillwatch-produktbrief.md). Det som är levererat markeras ✅. Inget är levererat i appen ännu.

## Etapp 0 — Verifiera integrationskontrakt

- ✅ Lokal inventering av skill-rötter och pluginmetadata ([rapport](research/lokal-inventering-2026-11-11.md))
- ✅ Verifiera att `skillFolderHash` = git-trädhash = GitHubs katalog-SHA
- ✅ Kompatibilitetsmatris från officiell dokumentation ([matris](research/kompatibilitetsmatris.md))
- ✅ Arkitekturbeslut 0001–0004
- [ ] **Teknisk spike** (Xcode-projekt): `MenuBarExtra`-panel + `Window`, mappväljare, läsning av `~/.claude` och `~/Library/Application Support/Claude` utan sandbox, Developer ID-signering och notarisering av en tom build. Bekräfta macOS 15 som lägsta version.
- [ ] Syntetiska fixtures: global/projekt/nästlad/symlänkad/delad/pluginägd/trasig `SKILL.md`, lockfil med matchande och avvikande hash, marketplace-klon som *inte* ska räknas.
- [ ] Läs `npx skills`-källkoden: exakt mappning agent → katalog för alla 15+ agenter, lockfilens schema per version.

## Etapp 1 — Läsande inventering

1. `SkillwatchCore`: `SKILL.md`-parser (frontmatter, tolerant mot fel, ingen exekvering).
2. Git-trädhash i Swift + fil-manifest (testat mot `git write-tree` på fixtures).
3. Discovery-motor: rötter från adapterregler, gränser för djup/filer/storlek, symlänkupplösning med loopdetektion, fysisk deduplicering, undantag.
4. Adapterregler v1: Claude Code, delad `~/.agents`, Cursor, Codex, Gemini CLI, OpenCode, Kiro, GitHub Copilot.
5. Proveniensadapter: `npx skills`-lockfil → källa + baseline-hash, `matchesBaseline`/`modified` lokalt.
6. Proveniensadaptrar läsande: Claude Code `installed_plugins.json`, Cursor plugin-cache, Codex `config.toml` → "Managed by …".
7. UI: menyradspanel (sammanfattning, senaste inventering), biblioteksfönster med sök/filter, detaljvy (sökväg, alias, agentkopplingar, källa, evidens), "Reveal in Finder", Coverage-vy.
8. Inställningar: projektmappar, egna rötter, undantag.
9. Filbevakning (FSEvents) med debounce + periodisk avstämning.

## Etapp 2 — Bevakning, diff och notiser (första kompletta MVP)

1. GitHub-källadapter: katalog-SHA via REST, ETag-cache, rate limit/backoff, offline/stale-status.
2. Uppdateringskontroll för lockfil-skills (R vs B) och plugin-commit-SHA:er där möjligt.
3. "Link source…" för okända skills: repo-URL, underkatalog, ref/policy. Försök innehållsmatchning mot historik.
4. Diffvy (filnivå + textdiff, markering av scripts/exekveringsbit).
5. SQLite/GRDB-lagring: policy, kandidater, notishistorik, check runs.
6. Schemaläggning (var 6:e timme, paus, efter sömn), deduplicerade notiser, sekretessläge.
7. Sparkle + DMG-pipeline + promosida (kan gå parallellt).

## Etapp 3 — Begränsade säkra uppdateringar

Enligt briefen §10. Första kandidat: skills som ägs av `npx skills`. Antingen delegera till `npx skills update`, vilket kräver capability-verifiering och Node, eller ersätta katalogen själva med transaktion, backup och rollback.

## Senare / idéer

- "Find more…": sök `SKILL.md` i vald katalog och föreslå nya rötter.
- Fler marketplaces (skills.sh-katalog, Claude Desktop-plugins).
- Visa vilka agenter en skill *saknas* i ("Install for Codex too?"), endast som information.
- Export/import av bevakningskonfiguration.
