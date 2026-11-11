# Kompatibilitetsmatris — skill-rötter och proveniens

**Kontrollerad:** 11 november 2026 · **Lokal maskin:** macOS 27.0.1, Claude Code 2.1.252

**Märkning**

| Märkning | Betydelse |
| --- | --- |
| **D** | Dokumenterat i officiell källa (länk i tabellen) |
| **3P** | Tredjepartskälla eller källkod |
| **L** | Observerat lokalt ([lokal inventering](lokal-inventering-2026-11-11.md)) |
| **H** | Hypotes, inte verifierad |
| **–** | Hittades inte |

Varje rad ska verifieras igen innan adapterregeln går till release. Sökvägar och format ändras ofta i det här ekosystemet.

## 1. Skill-rötter per agent

| Agent | Globala rötter | Projektrötter | Källa |
| --- | --- | --- | --- |
| **Claude Code** | `~/.claude/skills/` **D L**, `~/.claude/skills/synced/` (claude.ai, skrivskyddat, skrivs över) **D**, enterprise `/Library/Application Support/ClaudeCode/.claude/skills/` **D/H**, `CLAUDE_CONFIG_DIR` flyttar allt **D** | `.claude/skills/` i startkatalog och föräldrar upp till repo-roten, nästlade `<subdir>/.claude/skills/`, `--add-dir` **D** | [skills](https://code.claude.com/docs/en/skills), [managed settings](https://code.claude.com/docs/en/managed-settings) |
| **Cursor** | `~/.cursor/skills/`, `~/.agents/skills/`, kompatibilitet `~/.claude/skills/`, `~/.codex/skills/` **D**; inbyggda `~/.cursor/skills-cursor/` **L** | `.cursor/skills/`, `.agents/skills/`, `.claude/skills/`, `.codex/skills/`, nästlade **D** | [Cursor skills](https://cursor.com/docs/context/skills) |
| **Codex** | `~/.agents/skills/` **D**, `~/.codex/skills/` **3P L** (skill-installer skriver hit, saknas i officiell doc), `~/.codex/skills/.system/` **L**, admin `/etc/codex/skills` **D** | `.agents/skills/` från cwd upp till repo-roten **D** | [Codex skills](https://learn.chatgpt.com/docs/build-skills) |
| **Gemini CLI** | `~/.gemini/skills/`, `~/.agents/skills/` **D L**, extensions `~/.gemini/extensions/*/skills/` **D** | `.gemini/skills/`, `.agents/skills/` **D** | [Gemini CLI skills](https://geminicli.com/docs/cli/skills/) |
| **Antigravity** | `~/.gemini/config/skills/` **D L**, plugins `~/.gemini/config/plugins/*/skills/`, `~/.gemini/antigravity-cli/skills/`, legacy `~/.gemini/antigravity/skills/` **D** | `.agents/skills/` upp till repo-rot, legacy `.agent/skills/` **D** | [Antigravity skills](https://antigravity.google/docs/skills) |
| **GitHub Copilot / VS Code** | `~/.copilot/skills/`, `~/.agents/skills/` (+ `~/.claude/skills/` via Claude-harness) **D** | `.github/skills/`, `.claude/skills/`, `.agents/skills/` **D**; VS Code-extensions via `chatSkills` **H** | [GitHub](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills), [VS Code](https://code.visualstudio.com/docs/copilot/customization/agent-skills) |
| **OpenCode** | `~/.config/opencode/skills/` **D L**, `~/.claude/skills/`, `~/.agents/skills/` **D** | `.opencode/skills/`, `.claude/skills/`, `.agents/skills/` upp till rot **D** | [OpenCode](https://opencode.ai/docs/skills/) |
| **Amp** | `~/.config/agents/skills/`, `~/.agents/skills/`, `~/.config/amp/skills/`, `~/.claude/skills/`, **läser även** `~/.claude/plugins/cache/` **D** | `.agents/skills/`, `.claude/skills/` **D** | [Amp](https://ampcode.com/docs/customize/skills) |
| **Windsurf / Devin Desktop** | `~/.config/devin/skills/`, `~/.agents/skills/` **D**; `~/.codeium/windsurf/skills/` **3P** | `.devin/skills/`, `.agents/skills/`, `.windsurf/skills/` (legacy) **D** | [Devin Desktop](https://docs.devin.ai/desktop/cascade/skills) |
| **Factory Droid** | `~/.factory/skills/`, `~/.agents/skills/`, `~/.agent/skills/` **D** | `.factory/skills/` (nästlade), `.agents/skills/`, `.agent/skills/` **D** | [Factory](https://docs.factory.com/cli/configuration/skills) |
| **Kiro** | `~/.kiro/skills/` **D L** | `.kiro/skills/` **D** | [Kiro](https://kiro.dev/docs/skills/) |
| **goose** | `~/.agents/skills/`, `~/.claude/skills/`; `~/.config/goose/skills/` **3P** | `.agents/skills/`, `.goose/skills/`, `.claude/skills/` **D** | [goose](https://goose-docs.ai/docs/guides/context-engineering/using-skills) |
| **Junie, Cline, Roo** | `~/.junie/skills/`, `~/.agents/skills/`, `~/.roo/skills/` **3P** | motsvarande projektkataloger **3P** | [vercel-labs/skills agents.md](https://github.com/vercel-labs/skills/blob/main/docs/agents.md) |

**Slutsats:** `~/.agents/skills/` och `.agents/skills/` har blivit den gemensamma standardroten. Minst 10 agenter läser den. `~/.claude/skills/` och `.claude/skills/` är den näst vanligaste kompatibilitetsroten. En skill i någon av dessa är alltså synlig för många agenter samtidigt. Agentmärken i UI:t bör beräknas från adapterreglerna, inte från vilken katalog filen råkar ligga i.

## 2. Plugin- och marketplacesystem

| System | Installerat innehåll | Metadata | Maskinläsbart gränssnitt | Bedömning |
| --- | --- | --- | --- | --- |
| **Claude Code** | `~/.claude/plugins/cache/<mkt>/<plugin>/<version>/skills/*/SKILL.md` **D L**; gamla versioner får `.orphaned_at` och raderas efter 14 dagar **D** | `installed_plugins.json` (scope, installPath, version, `gitCommitSha` **L**), `known_marketplaces.json` (källrepo, autoUpdate), `known_marketplaces_claudeai.json`, `flagged-plugins.json` **D** | **`claude plugin list --json`** (id, version, scope, enabled, installPath, projectPath, errors) **D**; `claude plugin marketplace list --json` (fält odokumenterade) | Bäst stödd. Använd CLI i första hand och filer som reserv. `marketplaces/` är kloner och **ska inte räknas** |
| **Claude Desktop / Cowork** | `~/Library/Application Support/Claude/local-agent-mode-sessions/…` **L** | – | – | Interna sessionskopior. Visa som "Managed by Claude" och deduplicera. Låg prioritet |
| **Cursor** | `~/.cursor/plugins/cache/<mkt>/<plugin>/<commit-sha>/` **L**; lokal dev `~/.cursor/plugins/local` **D** | Manifest `.cursor-plugin/plugin.json` **D**; installationsmetadata – | – | Commit-SHA i sökvägen ger revision. Källrepo måste härledas (H) |
| **Codex** | `~/.codex/plugins/cache/<mkt>/<plugin>/<version>/` **D L** | Aktivering i `~/.codex/config.toml` `[plugins."x@y"]`, `[marketplaces.*]` **D L** | – (endast TUI `/plugins`) | Läs TOML. Undanta `~/.codex/.tmp/` (600+ katalogkopior) |
| **Gemini CLI** | `~/.gemini/extensions/*/skills/` **D** | – | `gemini skills list --all`, `gemini extensions list` (JSON –) | Läs kataloger |
| **Antigravity** | `~/.gemini/config/plugins/*/skills/` **D** | – | `agy plugin list --json` **D** | Lovande CLI. Verifiera format |

## 3. Installationsverktyg som lämnar proveniens

| Verktyg | Skriver till | Proveniensdata | Värde för Skillwatch |
| --- | --- | --- | --- |
| **`npx skills`** (vercel-labs) | Kanonisk `~/.agents/skills/<namn>` + symlänkar till valda agenters rötter **3P L**; `--copy` ger kopior | `~/.agents/.skill-lock.json` (eller `$XDG_STATE_HOME/skills/`): source, sourceUrl, skillPath, **skillFolderHash = git-trädhash**, installedAt, updatedAt; nyare versioner även `ref`, `pluginName`, `installMode` m.fl. **3P L**. Projekt: `./skills-lock.json` med `computedHash` **3P** | **Högst.** Exakt baseline och billig uppströmskontroll (verifierat, se [beslut 0004](../beslut/0004-innehallshash-git-trad.md)). Lokala lockfilen (v3) saknar några av fälten i källkoden, så schemat varierar mellan versioner |
| **openskills** | `.claude/skills`, `.agent/skills`, `~/.claude/skills` **3P** | Sidofil `<skill>/.openskills.json`: source, repoUrl, subpath, installedAt **3P** | Hög. Ger källa men ingen hash |
| **Codex skill-installer** | `~/.codex/skills/<namn>` **3P** | – | Ingen. Visa "Source unknown" och erbjud "Link source…" |
| **`gemini skills install`** | – | – | Okänt. Undersök senare |
| **`gh skill`** | – | – | Okänt. Undersök senare |
| **`amp skill add`** | `~/.config/agents/skills/` **D** | – | Okänt |

## 4. Agent Skills-specifikationen

[agentskills.io/specification](https://agentskills.io/specification) **D**:

- **Obligatoriskt:** `name` (1–64 tecken `[a-z0-9-]`, ska matcha katalognamnet), `description` (1–1024 tecken).
- **Valfritt:** `license`, `compatibility`, `metadata` (sträng→sträng; exempel `author`, `version`), `allowed-tools` (experimentellt).
- **Saknas i specen:** källa, version och proveniens. Därför finns ingen standardplats för proveniens, och verktygen löser det på egen hand (lockfiler, sidofiler).
- Agenter lägger till egna fält (Cursor: `paths`, `icon`, `color`; Claude Code: många). Parsern måste tolerera okända fält och visa valideringsfel utan att avbryta.

## 5. Öppna frågor (prioriterade)

1. Lockfilens schema per version i `npx skills`. Läs `src/skill-lock.ts` för de versioner som finns i omlopp och hantera v3 och senare.
2. ~~Exakta JSON-format för `claude plugin list --json`.~~ **Testat lokalt (2.1.252) L:** en array med `id`, `version`, `scope`, `enabled`, `installPath`, `installedAt`, `lastUpdated`, `mcpServers`. Matchar `installed_plugins.json` men lägger till `enabled`. `gitCommitSha` finns bara i filen. Kvar att avgöra: ska appen starta CLI:t som underprocess (kräver att `claude` hittas i PATH, vilket en GUI-app inte ärver) eller bara läsa filerna?
3. Cursor-plugins: kan källrepo härledas säkert från marketplacenamn och commit-SHA?
4. Var skriver `gh skill`, `gemini skills install` och Antigravity? Lämnar de metadata?
5. Hur ska sessionskopior i Claude Desktop representeras utan att skapa dubbletter?
6. Kör Claude Code på Windows/Linux med samma rötter? Irrelevant för macOS-appen, men påverkar fixtures om kärnan återanvänds.
