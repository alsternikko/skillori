# Kort i biblioteket · utredning 2026-11-16

Studien finns i `bibliotek-kort-2026-11-16/index.html`. Den är en enda fil och öppnas direkt från disk. Korten använder appens eget ljusfält: Pane-formen från `LightField.metal`, med samma tre uppmätta teman.

- Rose: uppdateringar
- Orchid: det du behöver titta på
- Meadow: det som är i ordning

Bilder ligger i `bibliotek-kort-2026-11-16/renders/`. `?still=8&c=A` ger en stillbild av ett koncept, och `pick=`, `sel=` och `done=` ger dess lägen.

Datan är riktig, från den här Macen i kväll:
- 349 skills
- 5 plugins med uppdateringar: 3 i Cursor (vercel, figma, superpowers) och 2 i Codex (slack, google-calendar)
- 9 skills utan känd källa, varav 2 finns i två versioner
- 1 skill som inte går att kontrollera
- Claude Code är i ordning sedan flora uppdaterades

En sak om utgångsläget: i 0.2.2 var den markerade rutan platt kolgrå. Ljusfältet fanns bara i menyradspanelens hero och i första starten. Alla fem koncept nedan låter korten bära ljuset.

## Alternativen

| | Idé | Styrka | Pris |
|---|---|---|---|
| **A · Three lights** | Tre kort: Updates, Look at, In order. Varje kort har sitt antal och, längst ner, var det görs. Trädet ligger under. Ett klick på ett kort släcker de andra och filtrerar trädet. | Enklast. Rutorna kommer tillbaka som tre riktiga ljusfönster, och att-göra-listan ligger inne i korten. Samma tre ljus som sajtens "Three lights". | En dag utan något att göra lyser bara Meadow, och de andra två är grå med en nolla. |
| **B · Product cards** | Ett kort per produkt (Cursor, Codex, Installed by you, Claude Code, Claude). Kortets ljus visar produktens läge. Ett klick gör alla kort till en hylla överst, med produktens träd under. | Svarar direkt på "var gör jag det?". Inga 349 rader innan man har valt. | Rutnätet blir trängre med fler agenter. Hur mycket som väntar syns i antalet kort som lyser, inte i en siffra. |
| **C · The deck** | Det som behöver dig ligger som en kortlek, ett kort i taget, med åtgärden på kortet. Trädet ligger till höger. Leken slutar med "Nothing needs you" i Meadow. | Mest fokuserat och har ett tydligt slut. Passar också i menyradspanelen. | Man ser inte allt som väntar på en gång. |
| **D · Light map** | Hela biblioteket som en karta. Varje ruta är så stor som antalet skills, och bara det som har något på gång lyser. | Det mest oväntade. Visar var tyngden ligger, till exempel att Codex är halva biblioteket. | Små plugins får ingen text. Den fungerar som en andra vy, inte som startvy. |
| **E · Rows that light up** | Listan är kvar, men grupper som behöver dig blir ljuskort på sin plats i trädet. | Minst förändring, och ljuset hamnar exakt där åtgärden är. | Känns mer som en lista än som kort. Korten flyttar sig när trädet fälls ut. |

## Rekommendation

A som startvy, med D som en andra vy ("Map") om det mest oväntade lockar. C passar som idé för menyradspanelen. B är ett starkt alternativ om produkterna, inte tillstånden, ska vara ingången.

## Öppet

- Mörkt läge är inte ritat.
- Hur A ser ut med noll uppdateringar (två grå kort och ett i ljus) bör provas i appen.
- Siffrorna i A räknar olika saker: plugins för Updates, skills för de andra två. Varje kort säger det i sin text.
