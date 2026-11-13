# Agentlogotyperna och leverantörernas varumärkesriktlinjer — 13 november 2026

**Status:** Beslutat av produktägaren 13 november, se [Beslut](#beslut-13-november) sist. Alla logotyper behålls; en rad om varumärken är tillagd i inställningarna.
**Gäller:** logotyperna i första start och på andra ställen där appen visar vilka agenter som finns på datorn. Se [`App/Skillori/AgentLogos/README.md`](../../App/Skillori/AgentLogos/README.md).
**Hur läsningen gjordes:** en läsande agent hämtade leverantörernas egna sidor den 13 november. Jag har inte läst om sidorna själv, och detta är ingen juridisk bedömning. Följ länkarna innan du bestämmer dig.

## Det viktigaste

- **Kiro strider mot AWS skrivna regler.** AWS tillåter namnet i löptext men inte logotypen utan skriftligt tillstånd. Den bör bort eller godkännas innan en release.
- **Codex och Gemini CLI kräver ditt beslut.** Båda leverantörerna har en väg för tillstånd som vi inte har gått.
- **OpenCode ser tillåten ut**, men vi bör byta till deras officiella kvadratiska fil.
- **Claude, Cursor och Antigravity** läses ur användarens egen installerade app och ligger inte i vår app. Ingen leverantör skriver något om det fallet.

## Läget per agent

| Agent | Hur vi visar den | Bedömning | Vad som avgör |
| --- | --- | --- | --- |
| Kiro (AWS) | Fil i appen | Inte tillåten som den är | Bara namn i löptext är fritt; logotyp kräver skriftligt tillstånd |
| Codex (OpenAI) | Fil i appen | Kräver ditt beslut | Villkorat tillstånd, men också "inte utan tillstånd" och "ändra inte" |
| Gemini CLI (Google) | Fil i appen | Kräver ditt beslut | Produktikoner ska godkännas via ett formulär |
| OpenCode (Anomaly) | Fil i appen | Ser tillåten ut | Förbjuder bara sken av stöd, namnbruk och produkter till försäljning |
| Claude (Anthropic) | Ikon ur installerad app | Kräver ditt beslut | Texten kräver förhandsgodkännande för all användning av märken |
| Antigravity (Google) | Ikon ur installerad app | Kräver ditt beslut | Samma allmänna Google-regler som Gemini CLI |
| Cursor (Anysphere) | Ikon ur installerad app | Ser tillåten ut, svagt underlag | Inga villkor publicerade, men heller inget uttalat tillstånd |

## Per leverantör

### Kiro (AWS)

- **Källa:** [AWS Trademark Guidelines](https://aws.amazon.com/trademark-guidelines/). Kiro har ingen egen varumärkessida.
- "Kiro" står i listan över AWS-märken (avsnitt 17).
- Avsnitt 13 tillåter hänvisande bruk som inte förvirrar kunder, men bara i text: "Any such use should be in plain text only (no logos)".
- Avsnitt 3(d) kräver skriftligt tillstånd i förväg för bruk utanför de listade licenserna. Avsnitt 9 förbjuder ändring av logotypbilder.
- **Kontakt för tillstånd:** ingen hittad.

### Codex (OpenAI)

- **Källa:** [openai.com/brand](https://openai.com/brand/). Användarvillkoren och tre hopfällda avsnitt på sidan gick inte att läsa.
- Riktlinjerna vänder sig till utomstående i allmänhet, också utvecklare.
- Tillåtet enligt sidan: använda logotypen när det direkt gäller OpenAI:s tjänster, exakt som den levereras, och ange att den tillhör OpenAI.
- Inte tillåtet: använda den utan tillstånd, ändra den, eller visa den mer framträdande än sin egen.
- Codex nämns inte vid namn.
- **Två saker som talar emot vårt sätt** (agentens slutsats, inte sidans ord): filen kommer från VS Code-tillägget och inte från den officiella nedladdningen, och beskärningen till rundad bricka kan räknas som ändring.
- **Kontakt för tillstånd:** partnercomms@openai.com.

### Gemini CLI och Antigravity (Google)

- **Källor:** [Brand Resource Center](https://about.google/brand-resource-center/guidance/), [hur Googles märken visas](https://partnermarketinghub.withgoogle.com/brands/google/branding-guidelines/how-to-show-googles-brand/), [samprofilering av produkter](https://partnermarketinghub.withgoogle.com/brands/google/use-cases/product-co-branding/), [Antigravitys villkor](https://antigravity.google/terms). De Gemini-specifika reglerna ligger bakom inloggning och är olästa.
- Att nämna Googles produkter i löptext är fritt.
- Produktikoner ska godkännas via ett formulär i Partner Marketing Hub.
- Kompatibilitet ska helst sägas i text. Ikoner bara när det behövs, till exempel i ett rutnät av kompatibla produkter, och utan att det ser ut att komma från Google.
- En rad om varumärkets ägare ska finnas med. Eget märke ska vara mer framträdande, och märkena får inte ändras.
- Gemini CLI:s kod har Apache 2.0, som inte ger någon rätt till logotypen som varumärke.
- "Antigravity" står inte i Googles varumärkeslista, som säger sig vara ofullständig.

### OpenCode (Anomaly)

- **Källa:** [opencode.ai/brand](https://opencode.ai/brand).
- Förbjudet: att antyda stöd eller sponsring, att använda namnet i ett produkt- eller företagsnamn, och produkter till försäljning utan tillstånd.
- Inget allmänt krav på tillstånd. Verktyg som fungerar med OpenCode får säga det.
- Logotypen beskrivs som avsedd för appikoner och små ytor, och det finns kvadratiska versioner med luft för ställen som beskär till kvadrat.
- Regler: ingen omfärgning eller effekter, minsta storlek 16 × 20 px, fritt utrymme på minst två streckbredder.
- **Att göra:** byta vår fil (webbplatsens apple-touch-icon) mot den officiella kvadratiska filen, oförändrad.
- **Kontakt:** press@opencode.ai.

### Claude (Anthropic)

- **Källor:** [Trademark Guidelines](https://www.anthropic.com/legal/trademark-guidelines), [Consumer Terms](https://www.anthropic.com/legal/consumer-terms).
- Märkena får bara användas så som Anthropic uttryckligen tillåter och i material som godkänts i förväg.
- Inga ändringar av färg eller proportioner, och inget sken av samarbete.
- Sidorna tar inte upp hänvisande bruk, kompatibilitet eller ikoner i andras gränssnitt.
- **Kontakt för tillstånd:** marketing@anthropic.com.

### Cursor (Anysphere)

- **Källor:** [cursor.com/brand](https://cursor.com/brand), [användarvillkoren](https://cursor.com/terms-of-service).
- Sidan erbjuder logotyper och appikoner för nedladdning. Den enda regeln gäller namnet: "Cursor", inte "Cursor AI".
- Inget krav på tillstånd och inga regler om ändring eller storlek, men heller inget uttalat tillstånd.

## Det ingen leverantör skriver om

Ingen sida skiljer på en logotypfil som ligger i vår app och ikonen från en app som användaren själv har installerat. För Claude, Cursor och Antigravity visar vi det senare, på samma sätt som Finder och programstartare gör: inget följer med vår app och inget sprids vidare. Att det fallet är lägre risk är vår slutsats, inte något en leverantör har sagt.

Ingen sida säger heller om en rundad bricka räknas som ändring av logotypen.

## Beslut som är dina

1. **Kiro:** ta bort logotypen och visa namnet på en neutral bricka, eller be AWS om tillstånd.
2. **Codex och Gemini CLI:** samma val — neutral bricka tills vidare, eller begära tillstånd (OpenAI via e-post, Google via formulär).
3. **Claude, Cursor och Antigravity:** behålla ikonen ur den installerade appen, eller behandla dem lika strängt som de andra.
4. **En rad om varumärken** i inställningarna och på webbplatsen, till exempel att alla produktnamn och logotyper tillhör sina ägare och att Skillori inte har något samarbete med dem. OpenAI och Google ber om något sådant.

En bricka utan logotyp finns redan i appen som reserv (två bokstäver), men du valde bort den 12 november till förmån för logotyper. Det valet behöver alltså vägas mot punkterna ovan.

## Beslut 13 november

Produktägarens svar på de fyra punkterna:

1. **Kiro:** logotypen behålls. Skälet: appen är liten, drar ingen vinning av deras varumärke och använder det inte för att kommunicera något eget.
2. **Codex och Gemini CLI:** behålls, av samma skäl. Inget tillstånd begärs.
3. **Claude, Cursor och Antigravity:** behålls som de är, med ikonen ur den installerade appen.
4. **Rad om varumärken:** ja. Den står nu sist i inställningarna: "All product names and logos belong to their owners. Skillori is not affiliated with or endorsed by them." Samma rad ska in på webbplatsen när den finns.

Det här är ett medvetet val att bära risken, inte en ny bedömning av reglerna. Bedömningarna i tabellen ovan står kvar: Kiros logotyp strider mot AWS skrivna regler, och OpenAI och Google har vägar för tillstånd som inte är använda. Om en leverantör hör av sig är åtgärden att byta den logotypen mot brickan med två bokstäver, som redan finns som reserv i appen.

Kvar att göra, oberoende av besluten: byta OpenCodes fil mot deras officiella kvadratiska version.
