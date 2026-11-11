# Lokal inventering — 11 november 2026

**Typ:** Lokala observationer (läsande). Inget har ändrats på maskinen.
**Maskin:** MacBook Pro M4 Pro, macOS 27.0.1 (26A434), Xcode 27.2, Swift 6.4.2, Claude Code 2.1.252.
**Metod:** `ls`, `find -name SKILL.md` med begränsat djup, läsning av JSON/TOML-metadata. Inga scripts i skills kördes.

Detta är *observationer på en maskin*, inte dokumenterade kontrakt. Se [kompatibilitetsmatrisen](kompatibilitetsmatris.md) för vad som är dokumenterat.

## 1. Sammanfattning

- Skills finns i **minst nio olika agentmiljöer** på denna dator, inte två. Det bekräftar att Skillwatch måste vara agent-agnostisk.
- Den vanligaste installationsvägen här är **`npx skills`** (vercel-labs/skills). Den lägger en kanonisk kopia i `~/.agents/skills/` och **symlänkar** in den i varje agents egen katalog.
- `~/.agents/.skill-lock.json` innehåller **källa och git-trädhash per skill**. Hashen är verifierad som identisk med både lokalt innehåll och GitHubs katalog-SHA. Det ger exakt proveniens och billig uppdateringsdetektion utan att klona något (se avsnitt 4).
- Plugin-system (Claude Code, Cursor, Codex, Claude Desktop) lägger skills i **versionerade cachekataloger**. Marketplace-kloner innehåller många `SKILL.md` som **inte** är installerade och får inte räknas.

## 2. Observerade rötter

| Rot | Innehåll | Typ |
| --- | --- | --- |
| `~/.agents/skills/` | 25 kataloger (riktiga) | Kanonisk plats för `npx skills`; även Cursor/Codex-kompatibilitetsrot |
| `~/.agents/.skill-lock.json` | 20 poster, `version: 3` | Proveniensmetadata från `npx skills` |
| `~/.claude/skills/` | 25 poster: 21 symlänkar → `~/.agents/skills/`, 4 riktiga kataloger | Claude Code personligt |
| `~/.cursor/skills/` | 1 symlänk → `~/.agents/skills/` | Cursor personligt |
| `~/.cursor/skills-cursor/` | 28 kataloger | Cursors inbyggda skills (ägarförvaltade) |
| `~/.codex/skills/` | 1 symlänk + `.system/` (5 skills, markörfil `.codex-system-skills.marker`) | Codex personligt + systemskills |
| `~/.gemini/skills/`, `~/.gemini/config/skills/` | symlänkar | Gemini CLI / Antigravity (två olika rötter!) |
| `~/.config/opencode/skills/` | 1 symlänk | OpenCode |
| `~/.kiro/skills/` | 1 symlänk | Kiro |
| `<projekt>/.cursor/skills/` | 13 poster i ett projekt under `~/My-projects` | Projektlokal Cursor |

### Pluginägt innehåll

| Plats | Observation | Metadata |
| --- | --- | --- |
| `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/` | 15 `SKILL.md` (1 plugin) | `installed_plugins.json` v2: scope, installPath, version, installedAt, lastUpdated, **gitCommitSha** |
| `~/.claude/plugins/marketplaces/<namn>/` | 63 `SKILL.md` | **Katalogkloner, inte installationer.** `known_marketplaces.json` ger källrepo |
| `~/.claude/plugins/plugin-directory-cache-v2.json` | Katalog med `repository.url`, `path`, `reviewed_commit` | Intern cache, schema okänt/instabilt |
| `~/.cursor/plugins/cache/cursor-public/<plugin>/<commit-sha>/` | 87 `SKILL.md` | Katalognamnet är en commit-SHA; `.cache-complete`-markör |
| `~/.codex/plugins/cache/<marketplace>/<plugin>/…` | 164 `SKILL.md` | Aktiva plugins i `~/.codex/config.toml` (`[plugins."x@y"]`, `[marketplaces.*]`) |
| `~/.codex/.tmp/plugins/`, `~/.codex/.tmp/bundled-marketplaces/` | 600+ `SKILL.md` | Temporärt/katalog — **ska undantas** |
| `~/Library/Application Support/Claude/local-agent-mode-sessions/…` | ~45 `SKILL.md` | Claude Desktop/Cowork-plugins per session; sökvägar innehåller UUID:n |

## 3. Viktiga mönster för discovery

1. **Symlänkar är normalfallet.** Samma fysiska skill syns i upp till 15 agentrötter. Deduplicering på fysisk identitet (realpath + inode) är ett krav från dag ett, inte en edge case. Både relativa (`../../.agents/skills/x`) och absoluta symlänkar förekommer.
2. **"Synlig för agent X" bör härledas från rot-tillhörighet**, inte från var filen ligger fysiskt. En skill i `~/.agents/skills/` utan symlänk i `~/.claude/skills/` är *inte* synlig för Claude Code (såvida inte Claude Code läser `~/.agents/skills/` – att verifiera).
3. **Hälften av alla `SKILL.md` på disk är inte aktiva installationer** (marketplace-kloner, tmp, staging). En naiv `find` ger fel svar. Varje adapter måste ange vilka underkataloger som är aktiva.
4. **Lock-filen täcker inte allt i sin egen rot.** 5 av 25 kataloger i `~/.agents/skills/` saknas i lock-filen (manuellt kopierade eller installerade med äldre verktyg) → ska visas som "Source unknown".
5. **`lastSelectedAgents`** i lock-filen listar 15 agenter som `npx skills` kan skriva till (amp, cline, codex, cursor, droid, fx, gemini-cli, github-copilot, kilo, kimi-code-cli, opencode, pi, warp, zed, claude-code). Användbart som lista över adapterkandidater, men verktygets egen mappning agent → katalog måste läsas ur dess källkod/dokumentation.

## 4. Nyckelfynd: `skillFolderHash` är en git-trädhash

Format (en post):

```json
"emil-design-eng": {
  "source": "emilkowalski/skills",
  "sourceType": "github",
  "sourceUrl": "https://github.com/emilkowalski/skills.git",
  "skillPath": "skills/emil-design-eng/SKILL.md",
  "skillFolderHash": "e79b9cc0…",
  "installedAt": "2026-04-24T08:44:03.284Z",
  "updatedAt": "2026-11-11T10:05:12.468Z"
}
```

**Verifierat 2026-11-11** för tre skills:

- `git write-tree` över den lokala katalogen (i ett isolerat temporärt git-index) ger **exakt** `skillFolderHash`.
- `gh api repos/emilkowalski/skills/contents/skills` returnerar katalog-SHA:er. För `animate`, `emil-design-eng` m.fl. är de **identiska** med lock-filens hash.

Konsekvenser för Skillwatch:

- **Lokal status (L vs B):** Beräkna git-trädhash för lokal katalog och jämför med `skillFolderHash` → `matchesBaseline` / `modified`. Kan göras i ren Swift (SHA-1 över git-blob/tree-format) utan git-binär och utan att köra något.
- **Upstream (R vs B):** Ett enda API-anrop per källrepo och katalog ger alla skills trädhashar → `unchanged` / `candidateAvailable`. Ändringar utanför skillkatalogen påverkar inte hashen, vilket uppfyller acceptanskriterium 6 gratis.
- **Proveniens för okopplade kopior:** Om en kopierad skills trädhash matchar en katalog-SHA i någon historisk commit i ett föreslaget repo, är matchningen *bevisad på innehållsnivå* vid den revisionen (men inte vem som skapade den).
- Samma teknik fungerar för Claude Code-plugins (`gitCommitSha`) och Cursor-plugins (commit-SHA som katalognamn) — att verifiera per adapter.

Begränsningar: git-trädhash beror på filläge (100644/100755/120000). Symlänkar inuti en skill och `.gitignore`-rade filer kan ge skillnader. GitHub API har rate limit utan autentisering (60/h) — cache och villkorliga anrop behövs.

## 5. Öppna frågor från inventeringen

- Läser Claude Code `~/.agents/skills/` direkt, eller bara via symlänkar i `~/.claude/skills/`?
- Varför har Gemini två rötter (`~/.gemini/skills` vs `~/.gemini/config/skills`) — CLI vs Antigravity?
- Är `installed_plugins.json`, Cursors plugin-cache och Codex `config.toml`-plugins dokumenterade eller interna format?
- Claude Desktops `local-agent-mode-sessions` innehåller sessionsspecifika kopior. Hur avgör vi vad som är "installerat" kontra en sessionsartefakt? Troligen: visa som ägarförvaltat, deduplicera på plugin-ID.
- Plugins i Claude Code-sessionen kommer delvis från claude.ai-kontot (t.ex. `anthropic-skills`, `figma`) och syns inte i `installed_plugins.json`.
