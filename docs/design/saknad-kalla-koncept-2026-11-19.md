# Skills vars källa saknas – utredning och koncept (2026-11-19)

Utgångspunkt: panelen säger "1 can't be checked · SOURCE NOT FOUND" och listan "Can't check" för `twombly`. Skillsidan säger "Nothing to do. The source was not found. It is private, renamed or removed." och erbjuder bara **Open source**, som leder till en 404-sida. Det är fel på två sätt: det finns något att göra, och källan finns – den har flyttat.

## 1. Vad som hände med twombly

| | |
|---|---|
| Installerad | 2026-11-10 med `npx skills`, låsfilen (`~/.agents/.skill-lock.json`) pekar på `materic-inc/twombly-skill`, `skills/twombly/SKILL.md`, `skillFolderHash 83b5287…` |
| Gamla repot | `github.com/materic-inc/twombly-skill` ger 404 utan omdirigering. Ett omdöpt repo omdirigeras, så det är raderat eller gjort privat – inte omdöpt. |
| Organisationen | `materic-inc` finns kvar, med de publika repona `plugins` och `open-layer-releases`. |
| Nya hemmet | `materic-inc/plugins`, mappen `twombly/skills/twombly`. Repots README säger: `npx skills add materic-inc/plugins --skill twombly`. |
| Bevis | Den installerade filen har git-hashen `646d306…`, samma som första versionen av filen i `materic-inc/plugins`. Mappens trädhash blir `83b5287…`, exakt låsfilens. Kontrollerat lokalt. Källan har sedan dess gått vidare (24 KB i stället för 930 byte), så det finns en riktig uppdatering att hämta. |
| Registret | skills.sh listar både den döda `materic-inc/twombly-skill/twombly` (417 installationer) och `materic-inc/plugins/twombly`. Hundratals andra har alltså samma trasiga post. |
| Fällor | `materic-inc/plugins` har två skills som heter `twombly` (`twombly` och `twombly-hosted`), så `--skill twombly` kan vara tvetydigt. Upphovspersonen levererar nu främst ett plugin (Claude Code, Cursor, Codex); den fristående skillen är sekundär. |

Slutsats: "not found" betyder ofta "flyttad", och Skillori har redan de verktyg som behövs för att bevisa det. Det som saknas är att leta på rätt ställen och att få flytta en skill som installatören redan har en post för.

## 2. Fallen där källan inte går att använda

| Fall | Hur det upptäcks | Vad användaren kan göra i dag |
|---|---|---|
| **Repot svarar 404** (installatörens post) | 404, eller 403 utan rate limit-huvuden → `.notFound` | Bara Open source (404-sida). Link, Find sources och Link and update är spärrade för skills med installatörspost. |
| **Mappen borta i repot** | Trädet hämtas men sökvägen finns inte → `.folderGone` | Samma som ovan. |
| **Länkad källa svarar 404** | Samma | Unlink, och sedan Link eller Find sources igen. |
| **Okänd källtyp** (posten pekar inte på GitHub) | `.unsupported` | Källkortet visar "Not known · Link…", men knappen gör ingenting för en skill med post. **En död knapp.** |
| **Ingen baslinje** i posten | `.noBaseline` | Ingenting. |
| **Ingen post alls** | `.noSource` | Link… och Find sources (fungerar). |

På den här Macen: 26 egna skills, 25 med post (alla GitHub), 1 länkad (`interface-craft`). Av 26 svar är 25 *up to date* och 1 *not found*, nämligen twombly.

## 3. Principer

1. **Säg vad som troligen hänt.** "Not found" ska inte sluta i "Nothing to do". Organisationen finns kvar men repot är borta, alltså flyttad eller borttagen. Repot finns men mappen är borta, alltså flyttad inom repot.
2. **Bevis före förslag.** Skillori föreslår bara en ny källa när innehållet bevisar det: samma mapp, samma SKILL.md, eller att din kopia finns i källans historik. Samma namn räcker inte, och en annan ägare med bara samma namn är ett leveranskedjerisk. Ett sådant fynd visas som "Same name" och kräver ett aktivt val, med en varning.
3. **Installatören äger posten.** Flytten görs med `npx skills add <nytt repo> --skill <namn> -g -y`, som skriver om låsfilen. Skillori skriver aldrig i låsfilen själv. Det är samma väg som *Link and update* redan går för okända skills.
4. **En rad, en knapp som gör saken** (regeln för "Things for you"). Hittas inget hem finns det inget att göra, och då hör det hemma som information, inte i listan.
5. **Sparsamt med GitHub.** Sök bara för skills som är `notFound` eller `folderGone`, högst en gång per dygn per skill, och använd svarscachen på disk. Webbsidor (`github.com/<ägare>`) och skills.sh kostar inget av API-kvoten.

## 4. Tre koncept

### A. Spårhunden (rekommenderas)
Skillori letar själv efter det nya hemmet när en källa försvinner, bevisar fyndet och erbjuder en knapp som flyttar och uppdaterar.

**Var den letar**, i den här ordningen, och stoppar vid första bevisade fynd:
1. **Samma repo, annan sökväg** (för `folderGone`). Trädet är redan hämtat. Leta efter en SKILL.md med samma `name` eller samma mappnamn och jämför hashar.
2. **Omdirigering.** GitHub följer redan ett omdöpt repo tyst. Skillori bör läsa det nya namnet i svaret och spara det, så att flytten kan föreslås med bevis direkt.
3. **Samma ägares andra repon.** Organisationen finns kvar (en hämtning av `github.com/<ägare>`). Lista dess repon och leta efter en mapp med skillens namn. För twombly hittas `materic-inc/plugins` här.
4. **skills.sh**, installatörens eget register. Sök på skillens namn och ta med kandidater som inte är den döda källan.
5. **Det Find sources redan gör**: mdskills.ai, repon dina andra skills kommer från, och kända samlingar.

**Bevis** via `SourceFinder.check`, som redan finns: identisk mapp, samma SKILL.md, eller äldre version i historiken. twombly ger *olderVersion*: din kopia är källans första version och källan har gått vidare.

**Vad användaren ser:**
- **Panelen**, i stället för "1 can't be checked · SOURCE NOT FOUND": `1 moved to a new source · Move` (knappen öppnar skillen i biblioteket).
- **Biblioteket, Things for you**: "twombly moved to materic-inc/plugins" – "Your copy is that source's first version, and it has changed since. Moving gets the new version and keeps it current." Knapp: **▶ Move and update**. Körningen visas i kommandoramen, med kvitto som vid en vanlig uppdatering.
- **Skillsidan**, rådet: "This skill moved". Källkortet visar den gamla källan överstruken, "Gone · materic-inc/twombly-skill", och under den "Now at materic-inc/plugins · twombly/skills/twombly". Knappar: **▶ Move and update**, **See source**, **Keep as is**.
- **Tvetydighet** (två `twombly` i samma repo): välj sökvägen som bevisas av hashen. Bevisar ingen av dem, visa båda med mappnamn och låt användaren välja.

**När inget hittas**: rådet blir "The source is gone" – "materic-inc/twombly-skill no longer answers. It may be private or removed. Your copy works as it is." Knappar: **Find sources** (sök med fler ställen), **Link…** (klistra in repo, adress eller curl-rad) och **Keep as local**. Det sista slutar kontrollera skillen, tar bort den från "can't be checked" och märker den *Local* i listan. Det går att ångra.

### B. Bara låsa upp det som finns
Minsta möjliga: tillåt Link…, Find sources och Link and update även för skills med installatörspost när källan är `notFound` eller `folderGone`. Lägg till **Keep as local**, och laga den döda Link…-knappen för okänd källtyp. Ingen automatisk sökning: användaren startar Find sources själv.
- Fördel: liten, säker, återanvänder allt.
- Nackdel: twombly hittas ändå inte, eftersom Find sources inte letar i ägarens andra repon eller i skills.sh. Användaren måste veta var den flyttat.

### C. Registret först
Fråga skills.sh om skillens namn och lita på det registret säger om var den finns nu.
- Fördel: billigt och träffar ofta, eftersom det är installatörens eget register.
- Nackdel: registret listar fortfarande den döda källan, och det säger inget om att innehållet är detsamma. Utan Skilloris hashbevis går en skill från en annan ägare inte att skilja från den rätta. Det duger som en av sökvägarna i A, inte som hela lösningen.

## 5. Rekommendation och ordning

Bygg **A ovanpå B**, i tre steg:

1. **Lås upp (B).** Link…, Find sources och Link and update för `notFound` och `folderGone` på skills med installatörspost. **Keep as local** med ångra. Panelraden får en knapp. Den döda Link…-knappen lagas. Texterna säger vad som troligen hänt i stället för "Nothing to do".
2. **Spårhunden letar (A).** Samma repo annan sökväg, sparad omdirigering, ägarens andra repon och skills.sh läggs till Find sources som källor. Sökningen körs automatiskt för försvunna källor, högst en gång per dygn. Fynd med bevis visas som "moved to …".
3. **Flytta och uppdatera.** Med installatörens `add`, tvetydighet hanterad med sökväg, och kvitto som vid andra körningar.

## 6. Att verifiera innan steg 3

**Provat 2026-11-20** i en tillfällig `HOME` med twombly och installatören 1.7.6 (samma resultat med 1.9.0):
- `add` med en befintlig post för samma namn **ersätter posten**. Det blir ingen dubblett, och länkarna i agentmapparna står kvar.
- `add materic-inc/plugins -s twombly` installerade **fel skill**, `twombly-hosted/skills/twombly`. `-s` tar den första som har namnet.
- `add materic-inc/plugins/twombly/skills/twombly` (ägare/repo/mapp) och `add https://github.com/…/tree/main/twombly/skills/twombly` tar rätt mapp. Tree-formen skriver också `ref: main` i posten. `tree/HEAD/…` fungerar inte.
- Därför använder Skillori nu mappformen när mappen är känd, både vid flytt och när länkade skills tas över. Appens egen väg (söka, länka, uppdatera) är körd hela vägen med sonden `SKILLORI_LOST_PROBE`. Den ger samma post och skillen *up to date* från `materic-inc/plugins`.

Kvar att fundera på:

- **403 utan rate limit.** Det räknas i dag som `notFound`. Bör det vara ett eget fall ("private")? En valfri GitHub-token (beslut 0003, etapp 3) skulle kunna låsa upp privata repon.
- **Plugin i stället för skill.** När upphovspersonen nu främst levererar ett plugin, ska Skillori säga det ("The author now ships this as a plugin for Claude Code, Cursor and Codex") och länka dit?

## 7. Ordlista för texterna (engelska i appen)

| Läge | Rubrik | Text |
|---|---|---|
| Flyttad, bevisad | twombly moved to materic-inc/plugins | Your copy is that source's first version, and it has changed since. Moving gets the new version and keeps it current. |
| Borta, inget hittat | The source is gone | materic-inc/twombly-skill no longer answers. It may be private or removed. Your copy works as it is. |
| Mappen flyttad i repot (exempel) | animate moved within emilkowalski/skills | It is now at skills/motion/animate. |
| Behållen lokalt | Kept as a local copy | Skillori no longer checks it against a source. |
| Panel | 1 moved to a new source | Knapp: Move |
