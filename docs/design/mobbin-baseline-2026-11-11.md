# Designbaseline från Mobbin — 11 november 2026

**Syfte:** Hitta designprinciper och mönster för Skillori i appar som är relevanta, antingen funktionellt eller för att de har ett eget, engagerande uttryck. Det här är en grund att diskutera nya visuella riktningar utifrån, inte ett beslut.
**Metod:** 11 sökningar i Mobbin via deras MCP (skärmar och flöden). Varje referens nedan har granskats som bild, inte bara via metadata. Länkarna går till Mobbin.

**Begränsning:** Mobbin täcker iOS och webb, inte macOS. Inga menyradsappar finns i underlaget. Mönstren behöver översättas till en liten panel och ett skrivbordsfönster.

## 1. Vad som skiljer de minnesvärda från de anonyma

Det mesta i de funktionella träffarna (uppdateringslistor, versionshistorik, integrationer) ser ut som vanliga SaaS-inställningar: ren lista, liten färgad etikett, ingen karaktär. Exempel: [Zapier versioner](https://mobbin.com/screens/a9e1cc70-7cfd-44f8-8c92-f910ed095fbd), [n8n community nodes](https://mobbin.com/screens/87a6f4d5-567d-4be8-b92e-c7bdbfcd5f4c). Våra tre första riktningar hamnade där. Varumärket fanns bara i symbolen och i en accentton, medan själva gränssnittet var anonymt.

Apparna som sticker ut lägger karaktären i **kärnobjektet eller kärninteraktionen**, inte i dekoren. Fyra tydliga källor till karaktär syntes:

| Källa | Vad det är | Referenser |
| --- | --- | --- |
| **Objekt/material** | Appens tillstånd är ett fysiskt föremål med en enda huvudhandling. Material och djup används på ett ställe, inte överallt. | [Brick](https://mobbin.com/screens/af0ece21-c6c1-4a83-963b-363ef79ca7ea), [(Not Boring) Camera](https://mobbin.com/screens/1c45bdad-c58a-430b-ac9a-bf59021fcfb1), [MD Vinyl](https://mobbin.com/screens/18683173-9b09-413c-8933-0f5e8108b189), [TIDE](https://mobbin.com/screens/a641b239-0e27-4b50-a830-ec0d6a050926) |
| **Instrument/precision** | Mätinstrumentets estetik: skalor, tickmarkeringar, monospace, exakta värden. Precision blir det vackra. | [Halide fokusskala](https://mobbin.com/screens/0df24593-7d15-4010-ab91-e7b66eb32995), [Raycast versionsskala i What's New](https://mobbin.com/screens/d6c1bb12-b0cc-4b14-b23d-e867e24b57b4) |
| **Figur/maskot** | En karaktär som reagerar på tillståndet och bär känslan i widgets och tomma lägen. | [How We Feel](https://mobbin.com/screens/4a37631d-8378-4a23-aacf-f523f89d7122), [Finch](https://mobbin.com/screens/d11b11e0-3abc-4c9a-8cc7-31e98c571367), [timespent](https://mobbin.com/screens/449f6e27-c4a7-4f46-b5f1-1cbdf19c0f2a) |
| **Typografi/redaktionellt** | Ett starkt typografiskt grepp och monokrom disciplin bär hela identiteten. | [stoic.](https://mobbin.com/screens/5b5d208c-3325-4639-96fa-fece5a08939e), [timespent What's New](https://mobbin.com/screens/708adb40-33a9-4bce-8876-783bf464d6dc) |

**Fråga till produktägaren:** Vilken av de fyra källorna, eller vilken kombination, ligger närmast det du såg framför dig? Svaret styr vilka referenser som är värda att samla.

**Svar 2026-11-11:** Produktägaren lutar mest mot **instrument/precision**. Det är en riktning, inget slutligt beslut. Referensinsamling och nästa visuella utforskning utgår från den. De övriga källorna kan fortfarande bidra med enskilda grepp.

## 2. Mönster per funktion i Skillori

### 2.1 Översikten: status som en hälsokontroll man kan agera på
- [NordVPN Dark Web Monitor](https://mobbin.com/screens/5a98517f-cbb6-4c8f-bdd4-9d6105dc3cd3): ett stort tillstånd ("1 leak detected") och en enda knapp ("Review and resolve").
- [Uber Account checkup](https://mobbin.com/screens/2abd59ac-3850-4271-95cc-b30df1e99257): en checklista där varje punkt har en statusmarkör och fälls ut på plats med sin åtgärd.
- [GoPay säkerhet](https://mobbin.com/screens/daa43c24-d077-41ec-aab3-aa3bc6bd037f): förlopp ("2/5 actions completed") och vad varje åtgärd ger.

**För Skillori:** Menyradspanelen ska visa *ett* tillstånd ("2 skills changed upstream", "All accounted for in 6 locations") och en nästa handling, inte en tabell med fyra siffror som i spiken. Detaljer fälls ut på plats.

### 2.2 Proveniens som en resa, inte en tabell
- [Shop leveransförlopp](https://mobbin.com/screens/16ce2d9c-a707-494b-b47d-39e484ecbd42), [Fly Delta bagagestatus](https://mobbin.com/screens/20079fa9-0814-46da-8c80-1ee86a780368), [Bolt Food](https://mobbin.com/screens/9509b853-f44c-425e-81c0-c6e96efffe2c): en tidslinje från ursprung till nu, där varje steg har plats, tid och status.

**För Skillori:** Det här är det tydligaste lånet. En skills historia är en resa: publicerad i `emilkowalski/skills` vid revision X, installerad med `npx skills` 16 okt, länkad in i Claude Code och 9 agenter till, ändrad lokalt? nej. Tidslinjen gör proveniens begriplig utan Git-kunskap. Det har briefen själv som mål (§17), och få verktyg gör det.

### 2.3 Uppdateringar och "What's New"
- [App Store uppdateringar](https://mobbin.com/screens/4d4f8151-b0d6-4a7a-a2ae-8b605fec267d): "Update All" ovanför en lista, per rad en avkortad versionstext med "more".
- [v0 extension marketplace](https://mobbin.com/screens/bcc629fe-8ac0-4b61-919f-4ddf02953ea4): per tillägg finns "Auto Update", flikar för Details och Changelog, samt Version, Published och Last released.
- [Clerk Updates](https://mobbin.com/screens/0d334b51-f362-45b1-a6a5-6c2cb42abac3): uppdateringskortet säger uttryckligen "you can revert back for the next 24 hours". Det är reversibilitet som förtroende.
- [Raycast What's New](https://mobbin.com/screens/d6c1bb12-b0cc-4b14-b23d-e867e24b57b4): versionsbyte via en liten skala med tickmarkeringar. Ett instrument i stället för en lista.

**För Skillori:** Skilj "ny version upptäckt" från "release notes". Visa alltid vad som går att ångra. Raycasts skala är en bra förebild för att bläddra mellan revisioner av en skill.

### 2.4 Granska ändringar (diff)
- [Google AI Studio "Viewing differences"](https://mobbin.com/screens/3430ca7f-87b3-4475-ba40-fe8258cf2687): diffen i ett modalt fönster med fällbara filer och "+10 lines changed". Lätt nog för en liten app.
- [Cursor](https://mobbin.com/screens/fa7df34d-7288-4c26-a0e9-95a84921e34e) och [Devin](https://mobbin.com/screens/e48cb198-fd26-4a92-b17a-a988aa5cbef8): filträd med +/- per fil, märkning av typen "New" och "Generated", och "Mark as viewed".
- [GitLab](https://mobbin.com/screens/95e376da-81cd-465c-a99b-a0051f9a2baf): växla mellan "Inline" och "Side-by-side".
- [Framer versioner](https://mobbin.com/screens/6074cf77-b523-4ee5-8046-c7f108612cf6): en versionslista med en detaljruta som listar *vad* som ändrades.

**För Skillori:** Börja med sammanfattningen (filer, rader, script markerade) och fäll ut till den fullständiga diffen. Script och körbara filer behöver sin egen märkning, enligt briefen §6.

### 2.5 Första start: förklara innan du ber om något
- [Klarna onboarding](https://mobbin.com/flows/ece82567-bc12-4466-8b01-35cf7132c1a0): tre korta löften med ikon, därefter samtycke.
- [Apple Health onboarding](https://mobbin.com/flows/67681ab9-670f-40ee-88ca-e60b77c7d46c): en konstellation av källor runt ett centrum ("brings your health information together in one place").

**För Skillori:** Apple Health-bilden är nästan exakt vår berättelse: alla dina agenters skills samlade på ett ställe. En konstellation av agenter runt Skillori, följd av tre löften (läser bara lokalt, laddar inte upp något, kör inga script), innan första skanningen.

### 2.6 Lugna lägen med personlighet
- [How We Feel](https://mobbin.com/screens/4a37631d-8378-4a23-aacf-f523f89d7122): "You're all caught up · Be kind to yourself today", med figurer.
- [Gusto](https://mobbin.com/screens/e0c3756d-cd7a-4268-ac01-fc6dfd1a630d): ett par ögon som klistermärke räcker.
- [Otter](https://mobbin.com/screens/ed2a964f-6db5-4296-82cd-51c2eaa9b37e): som jämförelse den anonyma versionen, en bock i en cirkel.

**För Skillori:** Personlighet hör hemma när inget behöver göras ("Nothing changed since Tuesday"). Den hör aldrig hemma i varningar eller fel.

### 2.7 Widget och små ytor
- [BitePal](https://mobbin.com/screens/487c5915-a34d-4bcf-aa0c-d07a42e93033), [Mimo](https://mobbin.com/screens/f5333bf0-bc83-4ccc-aa63-615816678920), [Alan](https://mobbin.com/screens/59d37b2f-8b61-4da5-8e95-e917a1b7f622): ett tal, en rad text och en figur som reagerar. Mer får inte plats.

**För Skillori:** Menyradspanelen fungerar som en widget. Den ska kunna läsas på en sekund. En framtida widget för macOS skrivbord och Notification Center är en naturlig förlängning.

## 3. Föreslagna designprinciper (baslinje)

1. **En huvudsak per yta.** Varje yta har ett tillstånd och en nästa handling (Brick, NordVPN).
2. **Karaktären bor i kärnan.** Uttrycket ska sitta i det objekt eller den interaktion som appen handlar om, inte i en symbol och en accentfärg.
3. **Proveniens som resa.** En skills ursprung visas som en tidslinje, inte som nyckel-värde-rader.
4. **Status man kan agera på.** Hälsokontroll med inline-utfällning i stället för en sifferpanel.
5. **Granska innan något ändras, och visa vad som går att ångra.** Diff-sammanfattning först och reversibilitet uttalad (Clerk).
6. **Precision som estetik.** Hashar, revisioner och tidsstämplar får vara vackra instrument (Halide, Raycast), inte undangömd metadata.
7. **Personlighet i lugnet, klarhet i allvaret.** Lekfullhet i tomma och färdiga lägen. Fel och varningar är raka och sakliga.
8. **Ärlig täckning.** Osäkerhet ("Source unknown", "Check failed", stale) visas lika tydligt som goda nyheter.

Principerna stämmer med produktbriefens krav (§2, §5, §6). De ändrar inget beslut i arkitekturen.

## 4. Nästa steg

- Produktägaren samlar visuella referenser. De fyra karaktärskällorna i avsnitt 1 kan fungera som sorteringsfack.
- Ny visuell riktning tas fram först när referenserna finns. Mönstren i avsnitt 2 gäller oavsett uttryck.
- Möjligt: spara de bästa referenserna i en Mobbin-samling. Inte gjort, kräver produktägarens ok.
