# Uppdatera plugins på gruppnivå: utredning och plan

16 november 2026. Utgår från tre skärmbilder av biblioteket i 0.2.2. Det som syns där:
- "Claude Code plugin · 15 plugin updates"
- "Cursor plugin · 63 plugin updates"
- "Codex plugin · 11 plugin updates"
- rutan Updates visar 89.

## Status 16 november, kväll

A och B är byggda på grenen `plugin-uppdateringar`. Provat på riktigt: flora-mcp-skills uppdaterades från appens egen körning, 0.11.1 → 0.11.5. Claude Code skrev ny `gitCommitSha`, och statusen blev Up to date efter omläsningen.

Under provet hittades två fel, som båda är rättade:
1. **Kontrollen efter en uppdatering köades men kördes aldrig.** Om en kontroll redan pågick sattes `checkAgain`, men den nya kontrollen såg fortfarande `isChecking` och lade sig bara i kö igen.
2. **GitHub svarar med commitens SHA som `sha` när man frågar efter ett träd via gren eller commit.** Rotens trädhash räknas nu ut ur posterna, som git gör. Det rättar även skills som ligger högst upp i ett repo: de visades tidigare alltid som uppdaterade.

## Tillägg samma kväll: ett konceptuellt grepp om hela vyn

Produktägaren påpekade att listan har flera snarlika namn: "Claude app", "Claude app plugin" och "Claude Code plugin", och motsvarande för Cursor och Codex. Hen bad om ett konceptuellt grepp, så att vyn blir enkel och tydlig och inte visar mer än läsaren behöver.

**Studie:** [`bibliotek-koncept-2026-11-16/index.html`](bibliotek-koncept-2026-11-16/index.html) är en fil som öppnas direkt från disk. Den visar tre koncept på riktig data från den här Macen, och renderingarna ligger i `renders/`.

**Varför namnen förvirrar:** de kommer från *mappen* en skill hittades i (`AdapterRules`-ägaren), inte från *produkten* läsaren använder. Fyra produkter blir därför sju namn:

| Ägarnamn i dag | Mapp | Produkt |
|---|---|---|
| Claude Code plugin | `~/.claude/plugins/cache` | Claude Code |
| claude.ai | `~/.claude/skills/synced` | Claude Code |
| Claude app | Claude-appens `skills-plugin` (från kontot) | Claude |
| Claude app plugin | Claude-appens `rpm` | Claude |
| Cursor, Cursor plugin | `~/.cursor/skills-cursor`, `~/.cursor/plugins/cache` | Cursor |
| Codex, Codex plugin | `~/.codex/skills/.system`, `~/.codex/plugins/cache` | Codex |

**Koncepten:**
- **A · Per produkt.** En rad per produkt, plugins under, och skills först när man öppnar en plugin. Plugins som inte går att kontrollera samlas på en lugn rad. Det är samma träd som i dag, en nivå djupare.
- **B · Att göra först.** Biblioteket öppnar med en kort lista över det som behöver läsaren, med var det görs, och har en lugn sammanfattning under. Exempel på punkter:
  - "3 plugins to update in Cursor", med versionerna
  - "frontend-design exists in two versions"
  - "9 skills have no known source"
- **C · Per agent.** Vad varje agent läser in. Den visar överlapp, men samma skill syns upp till sju gånger, och åtgärderna hör inte hemma hos agenter.

**Rekommendation:** A som struktur och B som startläge. C sparas som ett filter, "Seen by Cursor", i sökfältet. Planen nedan gäller A, alltså steg 1–3. B blir ett eget steg efter att produktägaren valt.

**Ändringar i planen efter studien:**
- Ordet "plugin" försvinner ur gruppnamnen: grupperna heter Claude Code, Claude, Cursor och Codex.
- Under Claude heter grenarna "From your Claude account" och "Plugins".
- Plugins som inte går att kontrollera samlas på en rad:
  - i Codex "N plugins updated by Codex"
  - annars "N plugins with no source to ask".
- Codex plugins visas med `interface.displayName` ur manifestet, till exempel "Adobe" i stället för `app-69312da8…`.
- Rutan Managed heter "From apps" och har bildtexten "in N plugins". Rutan Updates räknar saker att göra.

## Vad som är fel i dag

1. **Fel enhet.** Siffrorna räknar skills, inte plugins.
   - "63 plugin updates" är i själva verket tre plugins: vercel, superpowers och figma.
   - "15" är en plugin (flora), och "11" är två (slack och google-calendar).
   - Rutan Updates säger 89, men det finns sex saker att uppdatera.

   Briefen §6 säger att räknaren ska avse distributionsenheter, och att en plugin med fem skills inte ska ge fem uppdateringar.
2. **Fel nivå i trädet.** Grupperna är per ägare, och skills ligger direkt under. Det man uppdaterar, pluginen, syns inte som en rad.
3. **Ingen åtgärd för plugins.** Fältet längst ner, `groupBar`, finns bara för källgrupper (`kind == .source`, alltså `npx skills`). För plugins går det inte att göra något, inte ens en enskild skill.
4. **Ägarnamnen spretar.** Under "Managed by apps" finns "Cursor" (27 inbyggda) och "Cursor plugin" (73) som två grupper, liksom "Codex" och "Codex plugin", och "Claude app" och "Claude app plugin".

## Vad apparna själva kan göra (utrett 16 november)

| App | Kan uppdateras från kommandoraden? | Underlag |
|---|---|---|
| Claude Code 2.1.252 | **Ja.** `claude plugin marketplace update <marketplace>` hämtar marketplacen. `claude plugin update <namn@marketplace> --scope <scope>` uppdaterar pluginen ("restart required to apply"). | `claude plugin --help`, `claude plugin update --help` |
| Cursor | **Nej.** `cursor-agent` har bara `--plugin-dir` och inget kommando för installerade plugins. | `cursor-agent --help` |
| Codex | **Inte här.** Inget `codex`-kommando finns i PATH på den här datorn; Codex uppdaterar via appen. | `command -v codex` |

`claude plugin update` har flaggan `-y`. Den godkänner ett *ändrat installationskommando* som marketplacen anger, utan att fråga. Skillori ska **inte** skicka `-y`. Kräver uppdateringen ett sådant godkännande ska körningen stoppa, och appen ska be läsaren köra kommandot i Terminal och läsa vad som ändrats. Samma princip som för skills: verktyget som äger installationen skriver filerna, och Skillori godkänner aldrig något åt läsaren.

## Alternativ

**A. Fältet längst ner när en grupp är markerad.** Det läsaren föreslog. Mönstret finns redan för källgrupper, och ett fält som visas för markeringen passar med fältet för en enskild skill. Svaghet: med dagens träd markerar man "Cursor plugin" och får tre plugins i klump, utan att se vilka.

**B. Knapp i gruppraden när muspekaren är över den.** Snabbt, men tabellen är tät, knappen konkurrerar med statuschippet och går inte att nå med tangentbordet. Den bryter också regeln att åtgärder ligger i ett fast fält under listan, aldrig ovanpå den.

**C. Pluginen som egen nivå i trädet, och fältet längst ner för både app och plugin.** App → plugin → skills. Den nivå man markerar avgör vad fältet erbjuder:
- **App** markerad: "Uppdatera alla 3" (Claude Code) eller "Öppna Cursor" (Cursor och Codex).
- **Plugin** markerad: version gammal → ny, uppdatera eller öppna appen, Details och Open source.
- **Skill** markerad: som i dag, men statusen pekar på pluginen.

**D. En egen vy för uppdateringar** som listar allt som går att uppdatera, med en knapp per app. Bra som översikt, men rutan Updates fyller redan den rollen som filter. C ger samma sak när filtret är på.

## Rekommendation: C, med fältet från A

C löser alla fyra problemen, inte bara det med åtgärden. Fältet återanvänder det som redan finns (`groupBar`, `actionBar`, `CommandFrame`), så designen behöver inga nya delar.

### Trädet

```
MANAGED BY APPS · 317                                READ-ONLY HERE. EACH APP UPDATES ITS OWN.
├ + Claude Code            1 plugin · 15 skills                       ▲ 1 PLUGIN UPDATE
├ − Cursor                 6 plugins · 100 skills                     ▲ 3 PLUGIN UPDATES
│  ├ + vercel              33 skills     0.53.0 → 0.55.1              ▲ UPDATE IN CURSOR
│  ├ + superpowers         14 skills     6.1.1 → 7.0.2                ▲ UPDATE IN CURSOR
│  ├ + figma               16 skills     2.2.193 → 2.2.211            ▲ UPDATE IN CURSOR
│  ├ + gsap-skills          8 skills     1.0.0                        ● UP TO DATE
│  ├ + supabase             2 skills     0.1.4                        ■ MANAGED
│  └ + Built in            27 skills     set by the app               ■ MANAGED
├ + Codex                 25 plugins · 165 skills                     ▲ 2 PLUGIN UPDATES
└ + Claude app             2 plugins · 18 skills                      ■ MANAGED
```

- **Grupp per app,** inte per ägarsträng. "Cursor" och "Cursor plugin" blir en grupp, och de inbyggda skillsen hamnar under "Built in".
- **Pluginraden** har versionen i kolumnen Revision, så att kolumnen inte bara säger "set by the app".
- **Chippen räknar plugins.** En skill i en plugin med uppdatering får chippet "In plugin" i stället för ett eget "Plugin update", så den inte räknas en gång till.

### Fältet längst ner

Claude Code-gruppen markerad:
```
Claude Code   1 plugin has an update                        [▶ Update 1]  [Show command]
              Start a new Claude Code session afterwards to load it.
```

Cursor-gruppen eller en Cursor-plugin markerad:
```
Cursor        3 plugins have updates: vercel, superpowers, figma          [Open Cursor]
              Cursor updates its own plugins. Skillori can't do it from here.
```

En Claude Code-plugin markerad:
```
flora-mcp-skills   0.11.1 → newer at flora   [▶ Update]  [Details]  [Open source]
```

**Update** kör, genom samma `Shell` som skills (med Stop, tidsgräns och notis):

```
claude plugin marketplace update <marketplace>
claude plugin update <namn@marketplace> --scope <scope>     (inget -y)
```

Ett plugin med scope `project` körs med projektmappen som arbetskatalog. Efteråt läser appen om datorn och frågar källorna igen, precis som efter en skilluppdatering.

### Räknarna

- **Rutan Updates** räknar det man kan uppdatera, det vill säga egna skills plus plugins. Bildtexten blir till exempel "0 skills · 6 plugins".
- **Panelens rad** säger redan "N plugins have updates" och räknar plugins. Den behåller det.
- **Menyikonen** visar läget "new" när det finns något att uppdatera, oavsett enhet.

## Plan

Varje steg blir en egen commit, och allt samlas i en PR.

1. **Enhet och gruppering.** Gruppera managed per app (`PluginRecord.app`, plus en avbildning från ägarsträng till app för inbyggda skills). Lägg till pluginnivån i `SkillGroup`, eller en ny `PluginGroup`. Låt chippen och rutan Updates räkna plugins. *Test:* räkningen i `InventoryStore` (plugins, inte skills), och att Cursor och Cursor plugin blir en grupp.
2. **Fältet för app och plugin.** Utvidga `cursorGroupWithUpdates` och `groupBar` till managed-grupper och pluginrader, och låt `actionBar` visa pluginens version och knappar för en skill i en plugin.
   - Cursor och Codex: "Open Cursor" eller "Open Codex" via `NSWorkspace.openApplication`, och en mening om att appen uppdaterar själv.
3. **Uppdatering av Claude Code-plugins.** En `PluginUpdateRunner`, eller en utvidgad `UpdateRunner`, som kör de två kommandona ovan utan `-y`.
   - Den känner igen ett svar som kräver godkännande och visar det som "Review this update in Terminal", med kommandot att kopiera.
   - Notis när körningen är klar, som för skills.
   - *Test i självtestet:* argumenten är argument, inget `-y` skickas, och plugin-id godtas bara som `namn@marketplace` med säkra tecken.
4. **Panelen.** Raden "N plugins have updates" får länken Show, som öppnar biblioteket med filtret Updates.
5. **Verifiera på riktigt.** Uppdatera flora-pluginen från appen (0.11.1 → ny) och kontrollera:
   - att `installed_plugins.json` får ny `gitCommitSha`
   - att statusen blir Up to date efter omläsningen.

   För Cursor: kontrollera att "Open Cursor" öppnar rätt app, och att statusen följer med när Cursor har uppdaterat. Appen läser då om disken via mappbevakningen.

## Öppna frågor till produktägaren

- **Uppdatera alla plugins från Skillori?** Ska Claude Code-plugins gå att uppdatera härifrån, eller räcker det att visa kommandot? Briefen §10 säger "Öppna ägarverktyget; senare eventuell verifierad delegation". Att delegera till `claude plugin update` utan `-y` är en sådan delegation, men den skriver i `~/.claude`.
- **Rutan Updates:** ska den visa plugins och skills i samma siffra, eller bara egna skills med plugins i bildtexten?
