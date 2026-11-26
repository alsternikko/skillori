# 0005 — Produktnamn: Skillori

**Status:** Accepterat · 2026-11-11

## Kontext

Skillwatch var arbetsnamn i [produktbriefen](../Skillori-produktbrief.md). Produktägaren har utforskat namn vidare och valt **Skillori** (i namn- och varumärkesbriefen, som ligger utanför repot). Associationen *ori → origami* (ett ark som genom vikning får struktur) är en avsiktlig kreativ association, inte en språklig härledning.

## Beslut

- Produkt- och appnamn är **Skillori**. Det skrivs alltid så, aldrig SkillOri.
- Namnbytet gäller hela kodbasen nu, medan den är liten: appnamn, bundle-ID `com.niklaskarlsson.skillori`, Swift-paketet `SkilloriCore`, probe-verktyget `skillori-probe` och dokumentationen.
- Historiska dokument (produktbriefen och namnbriefen) behåller sitt ursprungliga innehåll och filnamn.
- Undertiteln är inte beslutad. "Your agent skills, accounted for." används inte förrän den prövats mot löftet om täckning ([0001](0001-agent-agnostisk-discovery.md): "alla skills i kända och valda rötter").

## Skäl

- Produktägarens uttryckliga preferens: namnet är tydligt och ligger bra i munnen, och det har en visuell idé (vikt papper) att bygga vidare på.
- Alternativet **Skillfold** används redan av ett open source-verktyg för Claude-skills med lockfil (`byronxlg/skillfold`, indexerat på skills.sh och skillsmp.com 2026-11-11). Det är samma nisch, alltså en risk för förväxling.
- Bundle-ID styr inställningar, nyckelringsposter och framtida Sparkle-uppdateringar. Att byta det efter en publik release kostar användarnas data, så bytet görs före första release.

## Kontroller 2026-11-11 (inte juridisk klarering)

| Kontroll | Resultat |
| --- | --- |
| Webbsökning "Skillori" | Inga träffar på namnet |
| `skillori.app`, `skillori.dev` (Google-registret via RDAP) | Ingen registreringspost |
| `skillori.com` (Verisign RDAP) | Registrerad 2022-10-07, löper till 2027-10-07. Ingen webbplats svarade |
| GitHub-konto `skillori` | Ledigt |

Inte kontrollerat: köpbarhet och pris hos registrar, varumärkesregister (EUIPO, USPTO, PRV), App Store-namn.

## Konsekvenser

- Nästa steg är visuella riktningar för symbol, menyradsikon och appikon. Vikningen ska ha en funktion i UI:t, till exempel plugin-grupper som vecklas ut (spikfynd 2).
- Projektmappen döptes om från `skillwatch` till `skillori` den 13 november 2026. Repot på GitHub heter `skillori`. Produktbriefen behåller sitt filnamn och arbetsnamnet Skillwatch i texten, eftersom den är ett historiskt underlag.
- Användarinställningar från spikbygget (UserDefaults under det gamla bundle-ID:t) följer inte med. Det är acceptabelt eftersom ingen release har gjorts.
