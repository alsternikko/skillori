# 0001 — Agent-agnostisk discovery

**Status:** Accepterat · 2026-11-11

## Kontext

Briefen nämner Claude Code och Cursor. Produktägaren har förtydligat att ambitionen är att hitta **alla** användarens skills, oavsett hur de installerats: marketplace, terminal, git, kopiering eller sätt vi inte känner till. Den lokala inventeringen ([lokal-inventering-2026-11-11](../research/lokal-inventering-2026-11-11.md)) visar skills i minst nio agentmiljöer, där samma fysiska skill ofta är symlänkad in i många av dem.

## Beslut

Discovery byggs i tre lager som samverkar:

1. **Formatet är det gemensamma.** En skill är en katalog med `SKILL.md` (Agent Skills-formatet). Skillwatch förstår formatet oberoende av agent.
2. **Adapterregister med deklarativa regler.** Varje agent/installationsverktyg beskrivs av en adapter: vilka rötter den läser (globalt och per projekt), vilka underkataloger som är aktiva respektive ska undantas (cache-arkiv, marketplace-kloner, tmp), vilken metadata som ger proveniens, och vilken version reglerna gäller. Adaptrar är så långt det går **data** (versionerad regelfil i appen), inte kod spridd i UI:t. Nya agenter ska kunna läggas till utan ändringar i kärnan.
3. **Egna rötter.** Användaren kan lägga till valfri katalog. Skills där visas med rotens namn och tillskrivs ingen agent automatiskt.

Därtill **proveniensadaptrar** som är oberoende av agent: `npx skills`-lockfil, Claude Code `installed_plugins.json`, Cursors plugin-cache, Codex `config.toml` osv. En skill kan alltså ha *agentkopplingar* från en adapter och *proveniens* från en annan.

Fysisk identitet (upplöst sökväg + filsystemets inode/device) är primärnyckel för en installation. Varje upptäckt sökväg blir en `AgentBinding`.

## Startuppsättning av adaptrar

Prioriteras efter observerad förekomst och dokumentation (se kompatibilitetsmatrisen): Claude Code, `~/.agents` (delad rot + `npx skills`-lock), Cursor, Codex, Gemini CLI, OpenCode, Kiro, GitHub Copilot, samt Claude Code-/Cursor-/Codex-plugins i läsande form. Övriga läggs till när dokumentation eller användardata visar behov.

## Konsekvenser

- Vi kan inte lova "alla skills på datorn". Löftet är "alla skills i kända och valda rötter", och vyn **Coverage** visar exakt vilka rötter som ingår.
- En valfri "Find more…"-funktion kan senare söka efter `SKILL.md` i en användarvald katalog och föreslå nya rötter. Den skannar aldrig hela hemkatalogen som standard.
- Adapterregler måste testas med fixtures per agent och märkas med verifieringsdatum.
