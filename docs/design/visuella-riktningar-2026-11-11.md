# Visuella riktningar för Skillori — 11 november 2026

**Status:** Underkänd av produktägaren 2026-11-11. Ingen av riktningarna når den nivå som eftersträvas. Behålls som historik; se [Mobbin-baseline](mobbin-baseline-2026-11-11.md) för vad som saknades.
**Canvas:** [Skillori visuella riktningar](https://claude.ai/artifact/NPHy2godiviY3M8SHg7wpv) (privat tills den delas)
**Underlag:** [Namn- och varumärkesbrief](../Skillori-namn-och-varumarkesbrief.md) §8–9 och §13, [spikfynd](../research/spike-2026-11-11.md)

Varje riktning visas i verkliga sammanhang: menyradsikon i 16 px i ljust och mörkt läge, förstorad mallbild, appikon i tre storlekar, menyradspanel och bibliotek med riktiga data från inventeringen (309 skills, varav 280 hanterade av appar). Symbolerna finns som mallbilder i [`symboler/`](symboler/).

Organisationens standarddesignsystem (Noira) användes inte. Det hör till en annan produkt, och briefen ber om ett eget uttryck med native macOS-känsla.

## Gemensamma principer

- **Papperets två sidor.** Ljusare ytor i symbolen är papperets baksida. I mallbilden för menyraden ritas de med 42 % täckning. I appikonen och UI:t får baksidan accentfärg. Det följer briefens §8.4 om färg på papperets insida.
- **Accentfärg skild från statusfärger.** Status använder grönt (Tracked), orange (Local changes), rött (Check failed) och blått (Managed). Accentförslagen ligger utanför dem: violett (A), magenta (B), petrol (C). Varje ritytas accent kan ändras under Tweaks.
- **Vikningen ska ha en funktion.** Spiken visade att 90 % av alla installationer ägs av plugins. Alla tre riktningarna visar därför plugins som hopvikta enheter som kan vecklas ut.

## Riktningarna

| | A · Vikt S | B · Hundöra | C · Origamiräv |
| --- | --- | --- | --- |
| Idé | En remsa vikt fyra gånger till ett S | Ett ark med vikt hörn betyder "mer att se" | En vikt räv, med innehåll som vecklas ut på plats |
| Läsbarhet i 16 px | Läses som S (testat i fyra varianter, se nedan) | Tydligast | Svagast, läses mer som en pil |
| Särprägel | Hög | Låg: liknar vanliga dokumentikoner | Hög, men liknar andra utvecklarverktygs rävlogotyper (t.ex. GitLab) |
| Gränssnitt | Native lista och detaljpanel. Utvikt innehåll ligger på en svag accentton | Kort med hundöron, plugins som buntar | En lista med detaljer som fälls ut i tre paneler under raden |
| Påverkan på det som byggts | Liten. Ligger närmast nuvarande bibliotek | Medel: kort i stället för lista | Större: detaljpanelen flyttar in i listan |
| Ordmärke | SF Pro, halvfet | SF Pro Rounded | Gemener, SF Pro medium |

## Vad som prövades och valdes bort

- **S med tre band och ett diagonalt mittband.** Lästes som Σ eller ett spegelvänt Z.
- **S med vågräta band heltäckande.** Läses som S i stor storlek men som "≡" i 16 px. Tonerna vändes därför: lodräta veck heltäckande, band ljusa.
- **Dragspelsvikt ark (första C).** Lästes som en dörr, en bok eller en högtalare och ersattes av räven. Utfällningsidén finns kvar i C:s gränssnitt.
- **Skillfold som namn.** Upptaget i samma nisch, se [beslut 0005](../beslut/0005-produktnamn-skillori.md).

## Rekommendation

**A · Vikt S**, med C:s inline-utfällning som möjlig senare förbättring om detaljpanelen blir trång.

- A läses som S i menyraden, är den mest särpräglade utan kända krockar, och bär hela origamiidén i en enda form.
- Gränssnittet ligger närmast det som redan byggts. Vikningen syns bara där den betyder något: utvikta grupper och den valda skillen.
- B är tydlig men generisk. C har mest personlighet men en verklig förväxlingsrisk och svag läsbarhet i 16 px.

Det här är en kreativ bedömning, inte ett resultat från användartester.

## Inte gjort

- Ingen riktning är testad i den riktiga appen, och ingen ikon är exporterad som `.icns` eller asset catalog.
- Ingen kontroll mot varumärkesregister eller logotypdatabaser.
- Typsnitt för ordmärket är systemtypsnitt (SF Pro). Ett eget ordmärke är inte ritat.
- Rörelse (utfällningsanimation, reducerad rörelse) är inte specificerad.
