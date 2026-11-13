# Visuell riktning "Readout" — 12 november 2026

**Status:** Omgång 3 är ritad i sin helhet och sedan byggd i appen. Appen är nu facit; skisserna på canvasen är inte uppdaterade efter den och visar bland annat det tidigare märket. Se [Byggt i appen efter skisserna](#byggt-i-appen-efter-skisserna-13-november).
**Canvas:** [Skillori – visuell riktning Readout](https://claude.ai/artifact/E4o4Z5GrzN1heWNrRM58ov) (privat tills den delas). Elva artboards.
**Bilder i repot:** [`readout-2026-11-12/v3/`](readout-2026-11-12/v3/). Tidigare omgångar finns i `v1/` och `v2/`.
**Underlag:** [Pinterest-referenserna](pinterest-referenser-2026-11-12.md), [typografin](typografi-2026-11-12.md), [Mobbin-baselinen](mobbin-baseline-2026-11-11.md), [UI-grunden](ui-bibliotek-utforskning.md).
**Ersätter:** de underkända [första riktningarna](visuella-riktningar-2026-11-11.md).

## Idén

Skillori är ett avläsningsinstrument för dina skills. Varje yta visar en avläsning i ett stort punkttal på ett solitt block. Blockets färg säger vad som gäller: kolsvart i vila, lime när något är nytt, lila när något behöver dig. Ett enda lager av glas ligger över blocken.

## Artboards

| Nr | Innehåll | Bild |
| --- | --- | --- |
| 01 | Menyradspanelen i tre tillstånd | [01-panel](readout-2026-11-12/v3/01-panel.png) |
| 02 | Biblioteket | [02-library](readout-2026-11-12/v3/02-library.png) |
| 03 | Detaljvy: typskylt, revisionsskala, proveniens | [03-detail](readout-2026-11-12/v3/03-detail.png) |
| 04 | Granska ändringar | [04-review](readout-2026-11-12/v3/04-review.png) |
| 05 | Färg, material, status, kontroller | [05-foundations](readout-2026-11-12/v3/05-foundations.png) |
| 06 | Typografi | [06-type](readout-2026-11-12/v3/06-type.png) |
| 07 | Mörkt läge | [07-dark](readout-2026-11-12/v3/07-dark.png) |
| 08 | Märket: ett S av femton punkter | [08-mark](readout-2026-11-12/v3/08-mark.png) |
| 09 | Första start i fyra steg | [09-first-start](readout-2026-11-12/v3/09-first-start.png) |
| 10 | Inställningar | [10-settings](readout-2026-11-12/v3/10-settings.png) |
| 11 | Tomma, lugna och felaktiga lägen | [11-states](readout-2026-11-12/v3/11-states.png) |

## Regler

1. **Grått först.** Kalla ljusgrå ytor, vita kort, svart text.
2. **Tre block med var sin betydelse.** Kolsvart: i vila. Lime: något nytt. Lila: behöver dig. Allt annat är grått.
3. **Färg ligger på hela block och brickor**, aldrig på text. Text på lime och lila är svart, text på kolsvart är vit.
4. **Block är solida och platta.** Inga skuggor eller övertoningar.
5. **Ett lager får vara glas:** panelen, en lista som skjuts upp över ett block, eller en svävande rad med åtgärder. Glas läggs aldrig på glas.
6. **Text på glas** kräver minst 60 % täckning bakom.
7. **Form och ord bär status, färgen bekräftar.**
8. **Ett stort punkttal per block.**
9. **Tre röster i typografin.** Punktsnittet för stora tal. Inter för namn och text. Mono för etiketter, data, status och knappar. Tyngsta vikt är 500.
10. **Varje värde är exakt, eller säger att det inte är det.** Ett gammalt resultat tonas ned i stället för att försvinna.

## Bärande grepp

| Grepp | Vad det är | Artboard |
| --- | --- | --- |
| **Tillståndsblocket** | Panelens översta block är lime, kolsvart eller lila efter tillståndet | 01 |
| **Listan i glas** | Listan under blocket är halvgenomskinlig och skjuts upp över blockets nederkant, så att färgen syns genom den | 01, 07 |
| **Statbrickor som filter** | Bibliotekets fem brickor visar antalen och filtrerar listan. Den valda är kolsvart | 02 |
| **Svävande åtgärdsrad** | En mörk glasrad över listan med den valda skillens åtgärder | 02, 04 |
| **Typskylten** | Skillens fakta som etikett: `ID`, `SOURCE`, `INSTALLED BY`, `FIRST SEEN`, `LOCAL COPY` | 03 |
| **Revisionsskalan** | En linjal på ett kolsvart block, med visare på installerad revision och lime fram till senaste | 03 |
| **Proveniensen** | En lodrät linje med ett hack per händelse och exakt tid. Ett steg som inte kan bevisas ritas som ett avbrott | 03 |
| **Diff** | Tillagt på lime, borttaget på grått med överstrykning, alltid med `+` och `-` | 04 |
| **Statusbrickor** | Rundad bricka med form och ord i mono | 05 |

## Tokens

### Neutraler

| Token | Ljust | Mörkt | Används till |
| --- | --- | --- | --- |
| `ground` | #E6E6E8 | #0E0E0F | Botten bakom fönster |
| `panel` | #F1F1F3 | #19191B | Fönster och panel |
| `card` | #FAFAFB | #242427 | Kort |
| `soft block` | #DCDCE0 | #2A2A2D | Lugnt block, borttagna rader |
| `line` | #EBEBEE | #303033 | Radlinje |
| `ink-3` | #A3A3A8 | #6E6E73 | Radnummer, ticks. Aldrig text som måste läsas |
| `ink-2` | #6B6B70 | #A6A6AB | Sekundär text |
| `ink` | #151516 | #F2F2F4 | Text, märken, primär knapp |

### Block

| Token | Värde | Betydelse | Exempel |
| --- | --- | --- | --- |
| `charcoal` | #1E1E1F | I vila | In sync, det valda, appikonen |
| `lime` | #BDF24B | Något nytt | Update available, tillagda rader, nya filer |
| `lilac` | #B592FF | Behöver dig | Check failed, lokala ändringar, script |

I mörkt läge behåller lime och lila sin ton, med svart text på. Neutralerna vänds, så det vilande blocket blir det ljusa (#F1F1F3). Lime och lila kan ändras under Tweaks på varje artboard.

### Material

| Lager | Värde |
| --- | --- |
| Panel i glas | Vit 80 % täckning, oskärpa 26 |
| Lista i glas | Vit 66 % täckning, oskärpa 18 |
| Mörk åtgärdsrad | Kolsvart 62 % täckning, oskärpa 20 |

### Form

- Hörn: 26–28 (panel), 20–22 (kort och block), 12 (rad, fält), fullt rundat (knappar, brickor).
- Kort ligger 6 punkter isär i en panel.
- Fokusring: 2 punkter `ink` med 2 punkters avstånd.

### Status

| Status | Form | Bricka |
| --- | --- | --- |
| In sync | Fylld punkt | Grå |
| Update available | Triangel | Lime |
| Check failed | Kryss | Lila |
| Local changes | Halv punkt | Lila |
| Source unknown | Bruten ring | Kontur |
| Linked by you | Ring med mitt | Grå |
| Managed | Kvadrat | Grå |
| Pinned | Romb | Grå |
| Old result | Öppen ring | Grå |

## Märket

> **Ersatt 13 november.** Märket nedan är omgång 3:s förslag. Det gällande märket är produktägarens egen teckning, se [Byggt i appen efter skisserna](#byggt-i-appen-efter-skisserna-13-november).

Ett S av femton jämnstora punkter på ett rutnät om fem gånger sju, enligt produktägarens referenser ([S av stora punkter](https://se.pinterest.com/pin/358317714128597959/), [bokstäver av punkter som byter form](https://se.pinterest.com/pin/338121884551090664/)).

| Rad | Punkter | Kolumner |
| --- | --- | --- |
| 1 | 3 | 2, 3, 4 |
| 2 | 2 | 1 och 5 |
| 3 | 1 | 1 |
| 4 | 3 | 2, 3, 4 |
| 5 | 1 | 5 |
| 6 | 2 | 1 och 5 |
| 7 | 3 | 2, 3, 4 |

- **Punktstorlek:** 92 % av rutnätets steg, så grannar nästan möts. 80 % och 70 % visas som alternativ.
- **Appikon:** ljusa punkter på ett kolsvart rundat kort.
- **Samma teckning i alla storlekar.** I 16 px blir varje punkt ungefär två pixlar, så menyradsikonen är märket självt.
- **Menyradens tillstånd:** hela S:et när allt stämmer, en uppsvälld övre ändpunkt vid uppdateringar, punkter som tänds i skrivordning vid kontroll, och nedtonat utan kontakt.
- **Rörelse:** femton punkter som flyttar sig mellan arrangemang. Bara beskriven, inte animerad.
- **Ordbild:** märket på kort med namnet i Inter, och en variant där märket står som första bokstav.
- **Kvadratiskt alternativ:** tretton punkter på fem gånger fem.

Märket och punktsnittets siffror bygger på samma rutnät, fem gånger sju. Det är avsiktligt: märket är en bokstav ur samma familj som talen.

## Första start, inställningar och lägen

Tillagda 12 november. Innehållet följer [produktbriefen](../Skillwatch-produktbrief.md) §6 och §11 där inget annat sägs.

### Första start (artboard 09)

| Steg | Block | Innehåll |
| --- | --- | --- |
| 1 Vad den gör | Kolsvart med märket | Tre löften: läser skillmappar på den här datorn, laddar inte upp något, kör aldrig ett script |
| 2 Var den letar | Grått med konstellation | Agenterna runt Skillori. Mappar som hittats, med reglage. Lägg till en projektmapp. Full Disk Access behövs inte |
| 3 Första avläsningen | Lime med antal skills | Egna, apphanterade och utan känd källa |
| 4 Hålla koll | Kolsvart med en fråga | Kontroll var sjätte timme, notiser, start vid inloggning |

- Notistillstånd begärs först i steg 4, när nyttan har visats. Det följer briefen.
- **Logotyper i konstellationen**, enligt produktägarens besked 12 november. Sju agenter visas med logotyp. Den åttonde noden är en vit bricka med "+2" för de två som inte får plats.
- **Var logotyperna kommer från:**

  | Agent | Källa | Hämtad som |
  |---|---|---|
  | Claude, Cursor, Antigravity | Appen som är installerad på produktägarens dator | Appikonen, via systemet |
  | Codex | OpenAI:s verifierade tillägg "Codex – OpenAI's coding agent" i VS Code Marketplace | Tilläggets ikon, 385 px |
  | Gemini CLI | geminicli.com | `/icon.png`, 1645 px |
  | OpenCode | opencode.ai | `/apple-touch-icon-v3.png`, 180 px |
  | Kiro | kiro.dev | `/apple-icon.png`, 192 px |

- Codex har ingen egen symbol i tillägget. OpenAI använder sin vanliga symbol på svart, och det är den som visas.
- De fyra hämtade bilderna är skalade till samma storlek som appikonerna. Codex, OpenCode och Kiro har fått samma rundade hörn som de andra. Inget annat är ändrat i dem.
- Logotyperna är uppladdade till canvasen. Filerna ligger inte i repot, men bilden av artboard 09 i `v3/` visar dem.
- **Förslag för appen:** `AgentMark` frågar systemet efter den installerade appens ikon, på samma sätt som Finder gör. För agenter utan app behövs en inbäddad logotyp eller en neutral bricka. Det är inte byggt eller prövat.
- **Inte gjort:** varumärkesriktlinjerna för agenterna är inte lästa. Det måste göras innan logotyper för Codex, Gemini CLI, OpenCode och Kiro bäddas in i appen.

### Inställningar (artboard 10)

| Grupp | Innehåll | Källa |
| --- | --- | --- |
| Checking | Av eller på, intervall på en tickskala, daglig sammanfattning, paus | Briefen |
| Notifications | Av eller på, dölj repo- och projektnamn | Briefen |
| Network | Fråga källorna, 60 anrop i timmen utan konto, token för privata källor i nyckelringen | Briefen och [inventeringen](../research/lokal-inventering-2026-11-11.md) |
| Folders | Hittade mappar, egna mappar, lägg till och ta bort | Befintlig vy |
| General | Start vid inloggning | Briefen |
| General | Menyrad med eller utan antal, utseende | **Mitt tillägg, inte beslutat** |
| Privacy | Samma text som i dagens inställningsvy, plus "No telemetry" | Befintlig vy och briefen |

Versionsnumret är en platshållare.

### Lägen (artboard 11)

| Läge | Block | Ton |
| --- | --- | --- |
| Före första skanningen | Grått, nedtonat `--` | Sakligt |
| Inget hittat | Grått, `0` | Sakligt, med en väg framåt |
| Inget nytt | Kolsvart, `0` | Lugnt, en varm rad |
| Sökning utan träff | Kort | Sakligt |
| Allt granskat | Kolsvart, `2/2` | Lugnt |
| En mapp kan inte läsas | Lila, `1` | Rakt: vad som saknas, varför och vad man gör |

Regeln från Mobbin-baselinen gäller: personlighet i lugnet, klarhet i allvaret. Ett fel visar aldrig ett tal som ser komplett ut.

## Byggt i appen efter skisserna (13 november)

Det här avsnittet beskriver det som skiljer appen från skisserna. Bilder ur appen finns i [`readout-2026-11-12/native/`](readout-2026-11-12/native/).

### Märket, version 2

Produktägarens egen teckning i Figma ersätter S:et med femton punkter. I koden är det `SkilloriMark` i `SkilloriUI`.

- **Rutnät:** sju gånger sju cirklar à 100 enheter med 20 enheters mellanrum, 820 enheter i kvadrat. Punkten är alltså 83 % av steget.
- **Frizon:** den yttersta ringen av celler är alltid tom. Den ska respekteras i både appikon och menyradsikon.
- **Symbolen** använder de inre fem gånger fem cellerna:

| Rad | Innehåll | Kolumner |
| --- | --- | --- |
| 1 | 3 punkter | 2, 3, 4 |
| 2 | 1 punkt och ett © | 1 och 5 |
| 3 | 3 punkter | 2, 3, 4 |
| 4 | 2 punkter | 1 och 5 |
| 5 | 3 punkter | 2, 3, 4 |

- **©-tecknet** är konturen ur Figma-filen, inte omritad. Under ungefär 64 px läses det som en ring med en prick i.
- **Appikon:** vita punkter på svart. Ikonfilen använder macOS standardplatta (824 av 1024 px med mjuka hörn) i stället för skissens hörnradie 100 av 820, eftersom macOS föreskriver ikonens ytterform. Hela rutnätet ligger på plattan, så frizonen blir avståndet till plattans kant.
- **Menyradsikon:** hela rutnätet i 22 pt utan bakgrund, som mallbild. macOS färgar den efter vad menyraden ligger på. Produktägaren valde det ("Följ systemet") framför fast vit och svart.
- **Menyradens tillstånd:** i läget "kräver dig" fylls ©-cellen med en hel prick, så frizonen hålls. Det är en svag signal i den storleken och inte godkänt av produktägaren. Utan aktuell avläsning tonas hela märket ned.
- **I appens ytor** ritas symbolen utan frizon, eftersom ytan runt den redan ger luft.

### Biblioteket som träd

Listan är ett träd i två nivåer, ritat med tunna linjer som i ett filträd i en terminal.

- **Rötter:** "Installed by you" och "Managed by apps".
- **Grenar:** en per källa, en för "No known source" och en per app som äger sina egna skills. Raden visar antal skills, antal agenter och en samlad status.
- **Löv:** varje skill, med sin sökväg inom källan, revision, agenter och status.
- **Öppna och stänga:** ett plus eller minus vid grenen. En gren öppnas också av sig själv när den är den enda, vid sökning, och när den innehåller den valda skillen.
- **Löpnumren är borta** ur listan. Detaljvyn räknar inom den egna roten, inte över båda.

### Inställningarna

Fönstret mäter sitt innehåll och blir exakt så högt, med samma marginal nedtill som på sidorna. Integritetsblocket är lika högt som vänsterkolumnen.

## Typografi

Oförändrad från omgång 2, se [typografin](typografi-2026-11-12.md). Punktsnittet Icomoon för stora tal, Inter för namn och text, Geist Mono för etiketter, data, status och knappar. Flersiffriga punkttal har 21 % teckenavstånd.

## Historik 12 november

| Omgång | Vad som ritades | Produktägarens besked |
| --- | --- | --- |
| 1 | Pappersgrå ytor, mono i allt, punktsnittet Doto, rödorange signalfärg, vikning struken | Mindre beige. Mjuka accenter. Doto konstig och forcerad, prova Icomoon. Lättare vikter. Ett gränssnittssnitt för text. Lyft kompositionen |
| 2 | Neutralt grått, kort i lax, lime och mint, Icomoon, Inter, Geist Mono, kort i rutnät | Paletten för stökig. Ta inspiration från [den här pinnen](https://se.pinterest.com/pin/540361655306597190/). Gillar solida block med genomskinlighet och oskärpa, som i [den här](https://se.pinterest.com/pin/563161128427314159/) |
| 2, märke | Morse för SKILL stansat i ett kort | Underkänt. För mycket prickar, stökiga kompositioner. Märket ska vara en genomarbetad form |
| 3, märke, första | Ett S i punktraster med varierande punktstorlek | Anpassa till ett S av prickar enligt två nya referenser |
| 3 | Det här dokumentet | Väntar på besked |

Bilder från tidigare omgångar: [`v1/`](readout-2026-11-12/v1/), [`v2/`](readout-2026-11-12/v2/), [`v3/studie/`](readout-2026-11-12/v3/studie/).

## Kompletterande Mobbin-referenser

Åtta sökningar gjordes 12 november efter hur etablerade produkter löser tekniska gränssnitt.

| Mönster | Referens |
| --- | --- |
| Mono i små versaler som etikett ovanför värden i sans | [Supabase projektöversikt](https://mobbin.com/screens/782baf2b-1d87-4a1c-a461-a87acc585ba9), [Render tjänstesida](https://mobbin.com/screens/1b400c9e-2ebe-45ad-9d14-83dca9bbd425) |
| Etikett inom hakparenteser, hårlinjer, sans i rubriker | [Grok API](https://mobbin.com/sites/sections/84432376-b340-47e9-8599-eac6ac716347) |
| Namn i sans, status och tider högerställda i mono | [Laravel Cloud driftsättning](https://mobbin.com/screens/dd29535f-34aa-4279-82fc-76e11059f596) |
| Hash i mono i en versionslista | [Cloudflare versionshistorik](https://mobbin.com/screens/2dfb1cd3-26ac-4e63-9866-f293a0306177) |
| Statusbrickor i mono och versaler | [Railway driftsättningar](https://mobbin.com/screens/cf56574a-01d3-4efe-b841-e091c9ecc39d) |
| Ljusgrå botten med vita rundade kort och små etiketter | [Linear projekt](https://mobbin.com/screens/344cad59-d4a8-421a-9c2f-14b3c977e82d), [Waymo](https://mobbin.com/screens/d4b7e27d-3ab4-464d-8b4b-72550f5b056b) |
| Staplade kort i färg | [Me+](https://mobbin.com/screens/8603b75c-65f6-43d7-ae36-8d5a0cb44f90) |
| Tre tal i rad med hårlinjer emellan | [Jomo](https://mobbin.com/screens/f6941747-53b6-4409-a1e0-19dccbd9c4ac) |

## Följder för `SkilloriUI`

| Komponent i [UI-grunden](ui-bibliotek-utforskning.md) §4.2 | Ändring |
| --- | --- |
| Tokens | Neutraler, tre block, material, hörn och typroller enligt ovan |
| `PanelHero` | Tillståndsblock med punkttal och mening |
| Ny: `GlassList`, `ActionBar` | Listan i glas över blocket, och den svävande åtgärdsraden |
| `RevisionScale`, `TickRuler` | Linjal på kolsvart block. `TickRuler` också som reglage |
| `StatusBadge` v2 | Statusbricka: form, ord i mono, grå, lime eller lila |
| `ProvenanceTimeline` | Lodrät linje med hack, exakt tid till vänster |
| `DiffSummary` | Brickor med punkttal och ett märke per rad |
| `FoldDisclosure`, `FoldedSurface` | **Utgår** |
| Ny: `StatTile` | Bricka med etikett, punkttal och en rad text. Används också som filter |
| Ny: `TypePlate` | Typskylten |
| Ny: egna kontroller | Knapp, segmentväljare, reglage, textfält |

Skalan med en tick per skill från omgång 1 och 2 finns inte längre i panelen. Den togs bort när blocket och glaslistan fick bära ytan.

## Risker

- **Glas och systemets material.** macOS 26 och senare har eget glas på fönster och paneler. Det talar för riktningen, men hur appens glas och systemets möts är inte prövat. På macOS 15 måste samma verkan byggas med `NSVisualEffectView`.
- **Läsbarhet över en stökig skrivbordsbild.** Panelen har 80 % täckning av det skälet. Det behöver prövas mot riktiga bakgrunder, och mot inställningen "Minska genomskinlighet".
- **Lila för "behöver dig"** är inte en inlärd betydelse. Orden måste alltid stå med.
- **Lime med svart text** är starkt. På stora ytor, som detaljvyns huvud, kan det bli tröttsamt.
- **Märket** har samma form som bokstaven S i många punktmatrissnitt. Det egna ligger i punktstorleken, kortet och rörelsen.
- **Punktsnittets ursprung är okänt.** `icomoon.ttf` anger bara "Font generated by IcoMoon". Licensen måste klarläggas innan fonten bäddas in.
- **Egna kontroller i hela appen** kostar tillgänglighet som systemkontrollerna ger gratis.

## Inte gjort

- Canvasen är kontrollerad som lokala renderingar av samma markup, inte i själva canvasvyn. Reglagen under Tweaks är inte provade.
- Inget är byggt i SwiftUI. Storlekar, avstånd och glas är ritade i en webbläsare.
- Kontrast är inte mätt.
- Mörkt läge är ritat för panelen och några kort, inte för alla vyer.
- Notiser och "Link source…" är inte ritade.
- Rörelse är inte specificerad.
- Märket är inte kontrollerat mot varumärkesregister, och inte finjusterat optiskt.
- Exempeldata bygger på inventeringen från 11 november. "2 changed upstream", revisionsnummer och andra hashar än `e79b9cc0` är påhittade för skissen.
