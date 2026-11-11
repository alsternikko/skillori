# Skillwatch

> Know your skills. See what changed.

En liten macOS-menyradsapp som visar vilka AI-agent-skills du har (oavsett agent och oavsett hur de installerats), varifrån de kommer och när källan har ändrats.

**Status:** Etapp 0 (research och arkitektur). Ingen app-kod ännu.

## Dokumentation

| Dokument | Innehåll |
| --- | --- |
| [Produktbrief](docs/Skillwatch-produktbrief.md) | Ursprunglig brief: mål, principer, statusmodell, etapper, acceptanskriterier |
| [Lokal inventering](docs/research/lokal-inventering-2026-11-11.md) | Vad som faktiskt finns på en riktig maskin |
| [Kompatibilitetsmatris](docs/research/kompatibilitetsmatris.md) | Per agent: dokumenterade rötter, pluginmekanismer, proveniens |
| [Beslut](docs/beslut/) | Arkitekturbeslut (ADR) |
| [Backlog](docs/backlog.md) | Prioriterade nästa steg per etapp |

## Arbetsregler

- Dialog, planer och dokumentation på svenska. Appens UI, notiser och felmeddelanden på engelska. Kodidentifierare på engelska.
- Allt skill-innehåll är opålitliga data. Ingenting körs vid inventering eller diff.
- Tester använder fixtures i temporära kataloger och ändrar aldrig riktiga installationer.
- Appen distribueras med Developer ID och notarisering utanför App Store (se [beslut 0002](docs/beslut/0002-distribution-och-sandbox.md)).
