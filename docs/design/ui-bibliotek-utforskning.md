# UI-bibliotek för Skillori — utforskning och rekommendation

**Datum:** 11 november 2026 (uppdaterad samma dag med Mobbin-baselinen)
**Status:** Underlag för beslut. Inga beroenden är tillagda och ingen kod är ändrad.
**Underlag:** [Produktbrief](../Skillwatch-produktbrief.md) §5–6 och §14, [namn- och varumärkesbrief](../Skillori-namn-och-varumarkesbrief.md), [beslut 0003](../beslut/0003-teknikstack.md), [spike](../research/spike-2026-11-11.md), [Mobbin-baseline](mobbin-baseline-2026-11-11.md) och koden i `App/Skillori/`.
**Arbetssätt:** Skillerna `pick-ui-library` och `emil-design-eng`.

## Sammanfattning

**Rekommendation:** Använd Apples egna ramverk som grund, alltså SwiftUI med AppKit där det behövs, så som beslut 0003 redan säger. Bygg ovanpå det ett eget komponentlager, `SkilloriUI`, med tokens för typografi, täthet, rörelse och statusvokabulär. Lägg inte till något tredjepartspaket nu. Fyra paket står på vänt med tydliga villkor för när de behövs. Inget hybridspår nu.

**Skälet i korthet:** Inget SwiftUI-paket ger ett bättre eget uttryck än det Apple redan levererar. Uttrycket bärs av egna komponenter, rörelse och typografi, inte av ett komponentpaket. Tredjepartskit som SwiftUIX och Pow ger mest bredd och effekter som inte passar en diskret app. Det enda område där webben är klart starkare är diffvyn med syntaxmarkering. Där ska native prövas först.

**Vad Mobbin-baselinen ändrar:** Valet av grund står kvar. Tre saker flyttar sig:

- **Karaktären flyttar till egna vyer.** Baselinen lägger karaktären i kärnobjekten: panelens tillstånd, proveniensens tidslinje och diffens sammanfattning. Ingen av dem är en Apple-kontroll. Därför väger begränsningen i SwiftUI:s listor mindre än jag först bedömde, men `SkilloriUI` växer från ett tunt lager till appens viktigaste del.
- **Panelen behöver fönsterkontroll tidigare.** Hälsokontrollen fälls ut på plats och ändrar panelens höjd. MenuBarExtraAccess, eller ett eget `NSPanel`, blir troligen nödvändigt redan i etapp 1.
- **Rive tillkommer på vänt.** Det behövs om produktägaren väljer figur eller maskot som karaktärskälla.

Bedömningen av hybridspåret står kvar och stärks snarare. Alla mönster i baselinen är sammansatta vyer som native bär bra, och en framtida widget kräver native.

**Om `pick-ui-library`:** Skillen förutsätter React och webben rakt igenom. Varje bibliotek i dess lista (Base UI, cmdk, Sonner, Motion, NumberFlow, shiki, Virtuoso, zustand med flera) kräver en webbvy för att kunna användas i Skillori. Jag har följt skillens arbetssätt: identifiera uppgiften, kontrollera vad som redan är installerat, rekommendera ett val och säga till när valet ligger utanför listan. **Alla native-rekommendationer nedan ligger utanför skillens kuraterade lista.**

## Vad som är verifierat och vad som är bedömning

| Märkning | Betyder | Källa |
| --- | --- | --- |
| **V** | Kontrollerat 11 november 2026 | GitHub API (senaste release eller tagg, licens, arkivstatus, `Package.swift`), npm-registret, SDK:ns `.swiftinterface` i Xcode 27.2 (`MacOSX27.2.sdk`) och Apple Developer Forums |
| **B** | Min bedömning | Erfarenhet och läsning av dokumentation, inte prövat i projektet |

**Inte gjort:** Inget paket är byggt eller provat i projektet. Swift 6-kompatibilitet med strikt samtidighetskontroll är inte provbyggd för något paket. Inget är mätt i fråga om minne eller prestanda för hybridspåret. Panelens beteende när innehållet ändrar höjd är inte prövat. Mobbin-referenserna har jag läst via baselinen, inte granskat själv.

**Nuläge i projektet (V):** `project.yml` och `Packages/SkilloriCore/Package.swift` har inga externa beroenden. All UI är SwiftUI med AppKit för `NSOpenPanel`, `NSWorkspace` och `NSApp`.

---

## 1. Behovslista

Behoven kommer från briefens §5–6 och §14, spikens fynd, Mobbin-baselinen och den kod som finns. Kolumnen *Egen komponent* anger om Apple inte har en färdig kontroll som räcker.

| Yta | Behov | Etapp | Native byggsten | Egen komponent |
| --- | --- | --- | --- | --- |
| **Menyradspanel** | Läses på en sekund. *Ett* tillstånd och en nästa handling, i stället för fyra siffror. Hälsokontroll som fälls ut på plats. "Last checked". Snabb att öppna och stänga | 1 | `MenuBarExtra(.window)` | **Ja:** hjälteobjekt, hälsokontroll, panelknappar |
| **Bibliotek** | Sök, filter på agent, projekt, källa, status och lokala ändringar. Plugins grupperade och utfällbara, egna skills först. 309 rader idag | 1 | `NavigationSplitView`, `List`/`OutlineGroup` eller `Table` med `DisclosureTableRow`, `.searchable` med tokens | Rad för distributionsenhet, filtertokens |
| **Detaljvy** | Proveniens som en tidslinje från ursprung till nu. Därunder verklig sökväg, alias, agentkopplingar, bevakningspolicy och "Reveal in Finder" | 1–2 | `ScrollView`, `LabeledContent`, `.inspector` | **Ja:** tidslinje |
| **Uppdateringar** | "Ny version upptäckt" skilt från release notes. Alltid uttalat vad som går att ångra | 2–3 | `Text`, `GroupBox` | **Ja:** uppdateringskort, ångra-rad |
| **Revisioner** | Bläddra mellan revisioner av en skill: baseline, lokal, kandidat | 2 | `ScrollView` med snäppning, `Canvas` | **Ja:** revisionsskala |
| **Diff-granskning** | Sammanfattning först (filer, rader, script markerade), sedan full diff. Fällbara filer, märkning (New, Script, Executable, Binary), "Mark as viewed", inline och sida vid sida. Stora diffar i eget fönster | 2 | Ingen färdig. `CollectionDifference` i standardbiblioteket ger raddiff | **Ja:** sammanfattning, fillista, diffvy |
| **Coverage** | Rötter, undantag, oläsbara platser, senaste inventering | 1 | `List` med sektioner (finns) | Nej |
| **Inställningar** | Projektmappar, egna rötter, undantag, bevakning, notiser, start vid inloggning | 1–2 | `Settings`-scen, `TabView`, `Form`, `SMAppService` | Nej |
| **"Link source…"** | Repo-URL, underkatalog, ref eller policy, hämtat innehåll bredvid lokalt före bekräftelse, etiketten "Linked by you" | 2 | `.sheet`, `Form`, `TextField`, `Picker` | Återanvänder diffvyn |
| **Onboarding och behörigheter** | En konstellation av agenter runt Skillori, sedan tre löften (läser bara lokalt, laddar inte upp något, kör inga script), sedan första skanningen. Notistillstånd när nyttan syns, ingen Full Disk Access | 1–2 | `Window`-scen, `Layout`, `NSOpenPanel`, `UNUserNotificationCenter` | **Ja:** konstellation, löften |
| **Lugna lägen** | Personlighet när inget behöver göras ("Nothing changed since Tuesday"), aldrig i varningar och fel | 1 | `ContentUnavailableView` är för anonym | **Ja:** lugnt läge |
| **Notiser** | Deduplicerade, "Review" öppnar appen, sekretessläge, fungerar utan systemnotiser | 2 | `UserNotifications` | Nej |
| **Statusmärken** | Status uttrycks inte bara med färg. Accentfärg hålls isär från statusfärger. Osäkerhet visas lika tydligt som goda nyheter | 1 | SF Symbols, `Text` | **Ja:** märke med form, ikon och text |
| **Tangentbord** | Native navigering, fokusmarkering, kortkommandon i menyer. Även egna komponenter som skalan och hälsokontrollen | 1 | `List`/`Table`, `@FocusState`, `.onKeyPress`, `.commands`, `.keyboardShortcut` | För egna komponenter |
| **VoiceOver** | Etiketter, grupperade element, rotor för status. Tidslinjen och skalan läses begripligt | 1 | `.accessibilityLabel`, `.accessibilityElement(children:)`, `.accessibilityRotor`, `.accessibilityAdjustableAction` | För egna komponenter |
| **Reducerad rörelse** | Färre och mjukare animationer, aldrig information som bara syns i en animation | 1 | `\.accessibilityReduceMotion` | Rörelsetokens som läser inställningen |
| **Tvärgående** | Ljust och mörkt läge, typografi, täthet, rörelse, två utseenden (macOS 15 och 26+) | 1 | Systemfärger, SF Pro, `controlSize` | **Ja:** tokens |
| *Senare: widget* | Ett tal, en rad, en figur (baselinen 2.7) | – | WidgetKit | Återanvänder hjälteobjektet |

---

## 2. Kandidater

### 2.1 Grund: Apples ramverk

Tillgänglighet kontrollerad i `SwiftUI.swiftinterface`, `SwiftUICore.swiftinterface`, `Symbols.swiftinterface` och `_WebKit_SwiftUI.swiftinterface` i SDK 27.2 (**V**). Deployment target är macOS 15. Allt utom de tre sista raderna kan alltså användas utan villkor.

| API | Lägsta macOS | Används till |
| --- | --- | --- |
| `MenuBarExtra`, `.menuBarExtraStyle` | 13 | Panelen (används redan) |
| `Table`, `OutlineGroup` | 12, 11 | Bibliotekets lista, grupperade plugins |
| `DisclosureTableRow` | 14 | Utfällbara plugin-grupper i en `Table` |
| `.inspector`, `ContentUnavailableView` | 14 | Detaljpanel, tomma sökresultat |
| `DisclosureGroupStyle` (öppet protokoll) | 13 | Egen "veckning" för hälsokontroll, grupper och detaljer |
| `Layout` (protokoll) | 13 | Radiell layout för konstellationen |
| `Canvas`, `TimelineView` | 12 | Tidslinjens räls, skalans tickmarkeringar, lugn tomgångsrörelse |
| `Gauge` med bl.a. `AccessoryCircularCapacityGaugeStyle`, `LinearCapacityGaugeStyle` | 13 | Möjligt instrument i panelen |
| `.scrollTargetBehavior`, `.scrollPosition(id:)` | 14 | Revisionsskala som snäpper |
| `PhaseAnimator`, `KeyframeAnimator` | 14 | Flerstegsrörelse, t.ex. vikning i onboarding |
| `.symbolEffect` | 14 | Diskret ikonrörelse vid statusändring |
| `.contentTransition(.numericText…)` | 13 | Räknare i panelen (motsvarar NumberFlow) |
| `.rotation3DEffect` | 10.15 | Enkel vikning med perspektiv |
| `Shader`, `.distortionEffect`, `.layerEffect`, `.colorEffect` | 14 | Metal-baserad pappersvikning och ljus om 3D-rotation inte räcker |
| `.visualEffect`, `.scrollTransition` | 14 | Positionsberoende effekter |
| `.onKeyPress`, `.sensoryFeedback` | 14 | Tangentbord, haptik i styrplattan när skalan snäpper |
| `TextRenderer` (protokoll) / `.textRenderer` | 14 / 15 | Egen textrendering och textanimation |
| `MeshGradient`, `.pointerStyle`, `.presentationSizing`, `.windowBackgroundDragBehavior` | 15 | Ytor, pekare, arkstorlek, fönsterbeteende |
| `\.accessibilityReduceMotion`, `.accessibilityAdjustableAction`, `.accessibilityRepresentation`, `.accessibilityRotor` | 10.15, 10.15, 12, 12 | Tillgänglighet, även för egna kontroller |
| `SMAppService.mainApp` (ServiceManagement) | 13 | Start vid inloggning, inget paket behövs |
| `.glassEffect`, `.backgroundExtensionEffect` | **26** | Bara bakom `if #available` |
| `DrawOnSymbolEffect` (SF Symbols "Draw") | **26** | Rita fram symbolen, bara bakom `if #available` |
| SwiftUI `WebView` | **26** | Hybrid måste använda `WKWebView` via `NSViewRepresentable` på 15 |

**Begränsning (V):** `ListStyle` har bara interna krav med understreck i namnet. Egna liststilar går alltså inte att skriva. Radinnehåll kan formas fritt, men markering, indrag och utfällningspilar följer systemet.

**Liquid Glass (V, via Apple Developer Forums):** En DTS-ingenjör bekräftar att `UIDesignRequiresCompatibility` ignoreras när appen byggs mot SDK 27 eller senare. Skillori byggs med Xcode 27.2. Appen får därför Liquid Glass på macOS 26 och 27 utan möjlighet att välja bort det, och det äldre utseendet på macOS 15. Uppgiften är inte kontrollerad mot release notes för Xcode 27.

### 2.2 Swift-paket

Versioner och status från GitHub API (**V**). Kolumnen *Bedömning* är **B**. Ett streck (–) betyder att uppgiften inte är kontrollerad.

| Paket | Version (datum) | Licens | Lägsta macOS | Löser | Bedömning |
| --- | --- | --- | --- | --- | --- |
| [MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) | 1.3.1 (2026-08-05) | MIT | 10.15 | Öppna och stänga panelen via kod, nå `NSStatusItem` och panelens `NSWindow` | **På vänt, troligen etapp 1.** Hälsokontrollen ändrar panelens höjd |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 3.1.0 (2026-09-11) | MIT | 10.15 | Användarvalt globalt kortkommando med inspelningskontroll | **På vänt.** Om produktägaren vill ha ett globalt kortkommando |
| [Textual](https://github.com/gonzalezreal/textual) | 0.5.0 (2026-06-15) | MIT | 15 | Rendering av Markdown och formaterad text i SwiftUI med markering, kodblock och syntaxmarkering | **På vänt.** Kandidat för renderad `SKILL.md`. Före 1.0, så exakt version måste pinnas |
| [Rive](https://github.com/rive-app/rive-ios) (`RiveRuntime`) | 6.29.0 (2026-10-30) | MIT | 13.1 | Spelar upp interaktiva vektoranimationer med tillståndsmaskiner, gjorda i Rives editor | **På vänt.** Bara om figur eller maskot väljs. Levereras som färdigbyggt binärt XCFramework (V) |
| [Lottie](https://github.com/airbnb/lottie-ios) | 4.6.1 (2026-06-13) | Apache-2.0 | 10.15 | Spelar upp animationer exporterade från After Effects | Avstå. Gjort för uppspelning. Rives tillståndsmaskiner passar en figur som reagerar på tillstånd bättre |
| [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | 2.4.1 (2024-10-13) | MIT | 12 | Markdown-rendering | **Avstå.** README: "MarkdownUI is in maintenance mode", utvecklingen sker i Textual |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) | 0.9.0 (2026-09-21) | Apache-2.0 | – | Markdown-parser (ingen vy) | Avstå tills vidare. `AttributedString(markdown:)` räcker för enkel text |
| [Highlightr](https://github.com/raspu/Highlightr) | 2.3.0 (2025-06-18) | MIT | 10.11 | Syntaxmarkering med highlight.js i JavaScriptCore | **Reserv** för diffvyn. JavaScriptCore under hardened runtime utan JIT-rättighet är inte verifierat |
| [swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) | 0.10.0 (2026-03-18) | BSD-3 | 10.13 | Tolkning med tree-sitter | Avstå. Kräver grammatikpaket per språk, för tungt för en granskningsvy |
| [STTextView](https://github.com/krzyzanowskim/STTextView) | 2.4.1 (2026-09-08) | **GPL-3.0 eller kommersiell** | 14 | Textvy på TextKit 2 | **Avstå.** Licensen passar inte en sluten app utan köpt licens |
| [CodeEditSourceEditor](https://github.com/CodeEditApp/CodeEditSourceEditor) | 0.15.2 (2025-09-16) | MIT | 13 | Komplett kodeditor | Avstå. En editor, inte en granskningsvy |
| [Pow](https://github.com/EmergeTools/Pow) | 1.0.5 (2024-11-10) | MIT | 12 | Färdiga övergångar och effekter | Avstå. Lekfulla effekter krockar med "diskret". Ingen release på två år |
| [Inferno](https://github.com/twostraws/Inferno) | tagg 1.1.0 | MIT | 12 | Exempel på Metal-shaders för SwiftUI | Referens, inte beroende. Läs tekniken och skriv egen vikningsshader vid behov |
| [SwiftUIX](https://github.com/SwiftUIX/SwiftUIX) | 0.3.2 (2026-09-18) | MIT | – | Bred samling tillägg | Avstå. Stor yta, liten nytta för Skillori |
| [swiftui-introspect](https://github.com/siteline/swiftui-introspect) | 27.1.0 (2026-10-07) | MIT | 12 | Når de underliggande AppKit-vyerna | Avstå tills ett konkret hinder finns. Eget `NSViewRepresentable` räcker oftast |
| [Settings](https://github.com/sindresorhus/Settings) | 3.1.1 (2024-05-07) | MIT | – | Inställningsfönster med flikar | Avstå. SwiftUI:s `Settings`-scen räcker |
| [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 1.1.0 (2023-12-21) | MIT | 13 | Start vid inloggning | Avstå. Ett tunt lager över `SMAppService` som vi kan anropa direkt |
| [fluid-menu-bar-extra](https://github.com/lfroms/fluid-menu-bar-extra) | – | MIT | – | Menyradspanel med mjuk storleksändring | **Avstå. Arkiverat** på GitHub. Behovet det löste blir aktuellt med hälsokontrollen |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.7 (2026-10-21) | MIT | – | Bildjämförelser i tester | Valfritt testberoende senare. `DebugSnapshots.swift` täcker behovet nu |

En GitHub-sökning efter färdiga SwiftUI-komponenter för diffvisning gav inga användbara träffar (**V**, `gh search repos`, 11 november 2026). Diffvyn blir egen kod oavsett val. Inte heller tidslinje, revisionsskala, konstellation eller hälsokontroll finns som paket värda namnet (**B**). De är enkla att bygga i SwiftUI.

[Sparkle](https://github.com/sparkle-project/Sparkle) 2.10.1 (2026-10-25) är redan beslutat i 0002 och är inget UI-bibliotek.

### 2.3 Webbspåret (bara för ett eventuellt hybridspår)

Versioner från npm-registret (**V**).

| Bibliotek | Version | Licens | Roll i ett hybridspår |
| --- | --- | --- | --- |
| [Base UI](https://base-ui.com) (`@base-ui/react`) | 1.9.0 | MIT | Tillgängliga primitiver i webbvyn |
| [Motion](https://motion.dev) (`motion`) | 14.12.0 | MIT | Rörelse i webbvyn |
| [Shiki](https://shiki.style) (`shiki`) | 4.6.0 | MIT | Syntaxmarkering med TextMate-grammatiker |
| [@pierre/diffs](https://github.com/pierrecomputer/pierre) | 1.6.4 | Apache-2.0 | Färdig diffrendering byggd på Shiki |
| React (`react`) | 19.3.1 | MIT | Krävs av Base UI och Motion |

cmdk 1.1.1 och Sonner 2.0.8 finns i skillens lista men behövs inte. Kommandopalett ingår inte i MVP, och notiser ska vara systemnotiser.

---

## 3. Jämförelse

### 3.1 Tre vägar

- **A. Native med eget komponentlager.** SwiftUI och AppKit. Egna komponenter och tokens i `SkilloriUI`.
- **B. Native med tredjeparts-UI-kit.** A plus SwiftUIX, Pow och liknande.
- **C. Hybrid.** Native skal, panel och listor. `WKWebView` med React, Base UI, Motion och Shiki eller @pierre/diffs för diffvyn och eventuellt detaljvyn.

Ett fullt stackbyte till Tauri eller Electron utvärderas inte här. Briefen §12 avfärdar det för första versionen, och ett byte är produktägarens beslut.

| Kriterium | A. Native + eget lager | B. Native + UI-kit | C. Hybrid |
| --- | --- | --- | --- |
| Täcker behovslistan | Allt med egna komponenter. Diffvyn är största enskilda arbetet | Samma som A. Kiten tillför inget av baselinens mönster | Diffvyn nästan färdig. Resten native ändå |
| **Rörelse** | Fjädrar, `PhaseAnimator`, `KeyframeAnimator`, `matchedGeometryEffect`, Metal-shaders. Räcker gott för vikning (B) | Färdiga effekter, men generiska och lekfulla (B) | Motion är utmärkt, men bara inne i webbvyn. Övergångar över gränsen native/webb blir sömmar (B) |
| **Detaljer** | Egna `ButtonStyle`, `DisclosureGroupStyle`, `LabelStyle`. SF Symbols-effekter. Haptik i styrplattan (B) | Lägger till bredd, inte precision (B) | Webbens detaljverktyg är rikast, men måste efterlikna macOS för att inte kännas främmande (B) |
| **Typografi** | SF Pro med bredder (`.fontWidth`), New York, SF Mono, egna inbäddade typsnitt, `TextRenderer` (B) | Som A | Fri typografi, men två renderingsmotorer i samma app (B) |
| **Täthet** | `controlSize`, radhöjd, kolumner i `Table`. Begränsad av stängda liststilar (V) | Som A | Full kontroll i webbvyn (B) |
| Tangentbord, VoiceOver, reducerad rörelse | Gratis i `List`/`Table`/`Form`. Egna komponenter kräver eget arbete, men med native API:er (B) | Varierar per paket (B) | Fokus mellan native och webb och VoiceOver i webbvy kräver eget arbete och test (B) |
| macOS 15 och 26+ | Följer systemet automatiskt i båda (V för Liquid Glass-nyckeln) | Kit kan ligga efter nya systemutseenden (B) | Webbvyn följer inte Liquid Glass alls (B) |
| Widget senare | WidgetKit, samma SwiftUI-komponenter (B) | Som A | Webbvyn kan inte användas i en widget (B) |
| Opålitligt innehåll (briefen §11) | Text i `Text`/`AttributedString` körs aldrig (B) | Som A | Kräver strikt CSP, ingen JavaScript från innehåll och noggrann escaping (B) |
| Resurser | En process, ca 90 MB RSS idag (V, spiken) | Marginellt mer | Egen WebContent-process och ett JS-paket i appen. Inte mätt (B) |
| Beroenderisk | Inga externa beroenden | Flera breda paket, ett utan release på två år (V) | npm-kedja, byggsteg och två verktygskedjor (B) |
| Arbetsinsats | Medel till hög: ett tjugotal egna komponenter, de flesta små | Låg i början, hög vid avvikelser | Hög: brygga, byggsteg, säkerhet, dubbla designspråk |

### 3.2 Var native begränsar uttrycket

1. **Listans ram följer systemet (V).** Markering, indrag och utfällningspilar går inte att göra egna. Baselinens princip 2, "karaktären bor i kärnan", lägger dock karaktären i panelens tillstånd, proveniensens tidslinje och diffens sammanfattning. Alla tre är egna vyer där listans begränsning inte gäller. **Begränsningen väger därför mindre än jag först bedömde (B).** Biblioteket får vara lugnt och native. Att bygga listan själv med `ScrollView` och `LazyVStack` kräver egen tangentbordsnavigering, typsökning, flerval och VoiceOver-tabellsemantik. Jag avråder fortfarande från det.
2. **Två systemutseenden (V).** Samma kod ser olika ut på macOS 15 och 26+. Karaktärskällan *objekt/material* är mest utsatt: ett eget material i panelen möter systemets glas. *Typografi* och *instrument* påverkas minst (B).
3. **Panelens storlek (B, inte prövat).** Hälsokontrollen fälls ut på plats och ändrar panelens höjd. `MenuBarExtra` saknar API för panelens fönster (V, enligt MenuBarExtraAccess README). Om höjdändringen hoppar i stället för att glida krävs MenuBarExtraAccess eller ett eget `NSPanel`.
4. **Ingen färdig diffvy (V).** Den blir egen kod. Sida vid sida är det dyraste läget. Sammanfattningen först minskar behovet av den fulla diffen (B).
5. **Ingen editor för figurer (B).** En figur som ritas i kod med `Shape` och `KeyframeAnimator` fungerar för enkla tillstånd. En figur som en illustratör ska rita och ge många tillstånd kräver Rive.

### 3.3 Mobbin-baselinen mot native

**Karaktärskällorna** (baselinen §1). *Bär det* är **B**. API-versioner är **V**, se 2.1.

| Källa | Bär SwiftUI/AppKit det? | Hur | Nya komponenter |
| --- | --- | --- | --- |
| **Objekt/material** | Bra | Former, gradienter, `MeshGradient` (15), skuggor, `.rotation3DEffect` för veck, Metal-shaders (14) för papperets ljus. Materialet på ett ställe: panelens hjälteobjekt och detaljvyns huvud. Kostnaden är designarbete, inte bibliotek. Glaset på macOS 26+ är systemets ram, vårt objekt ligger i innehållet | `PanelHero`, `FoldedSurface` |
| **Instrument/precision** | Mycket bra | SF Mono, `.monospacedDigit()`, `.fontWidth`, tickmarkeringar i `Canvas` (12), snäppning med `.scrollTargetBehavior` (14), haptik med `.sensoryFeedback` (14), `Gauge` (13). Skalan nås med piltangenter och exponeras för VoiceOver med `.accessibilityAdjustableAction` | `RevisionScale`, `TickRuler`, `RevisionChip` |
| **Figur/maskot** | Delvis | Enkla figurer ritade i kod med `PhaseAnimator`/`KeyframeAnimator` (14). En tecknad figur med många tillstånd kräver Rive 6.29.0. Figuren ryms inte i menyradens 16 px-mallbild (namnbriefen §8.1). Den lever i panelen och i lugna lägen | `Figure` med tillstånd, värd i `CalmState` och `PanelHero` |
| **Typografi/redaktionellt** | Mycket bra | Inbäddade typsnitt, `.fontWidth`, `.fontDesign(.serif)`, `.tracking`, `TextRenderer` (15) för animerad text. Monokrom disciplin är lätt med semantiska tokens. Systemets ram (verktygsfält, sidofält, menyer, inställningar) behåller systemtypsnittet. Det redaktionella greppet lever i innehållsytorna | Typroll `display`, `DisplayNumber` |

**Mönstren** (baselinen §2).

| Mönster | Bär SwiftUI/AppKit det? | Vad som krävs | Nya komponenter |
| --- | --- | --- | --- |
| **Hälsokontroll i panelen** (2.1, 2.7) | Bra, med en reservation | Ett tillstånd och en nästa handling överst. Punkter med statusmarkör som fälls ut på plats via en egen `DisclosureGroupStyle`. Reservationen är panelens höjd, se 3.2 punkt 3 | `PanelHero`, `HealthCheckList`, `HealthCheckItem`, `NextActionButton` |
| **Proveniens som resa** (2.2) | Bra | Lodrät tidslinje i `VStack` med en räls i `Canvas`. Varje steg har plats, tid och status. Ett okänt steg ritas som ett avbrott i rälsen med text, så att osäkerheten syns (baselinen princip 8). För VoiceOver blir varje steg ett element ("Installed with npx skills, 16 Oct, verified"). Detaljvyn går från `Form(.grouped)` till `ScrollView` med egna sektioner | `ProvenanceTimeline`, `TimelineStep` (ersätter `EvidenceRow`) |
| **Vad som går att ångra** (2.3) | Bra | Mest innehåll och struktur. Tre lägen: "Nothing changes until you approve" (etapp 2, inga skrivningar), "You can undo until …" (etapp 3, backup), "Can't be undone here. Managed by …" | `UpdateCard`, `ReversibilityNote` |
| **Revisionsskala** (2.3, Raycast) | Bra | Vågrät skala där varje tickmarkering är en revision (baseline, lokal, kandidat). Följer pekaren direkt, snäpper med fjäder, haptik vid snäpp, piltangenter | `RevisionScale` |
| **Diff med sammanfattning först** (2.4) | Bra för sammanfattning och inline. Delvis för sida vid sida | Sammanfattning: filer, +/− rader, script och körbara filer markerade. Fillista med fällbara filer och "Mark as viewed". Inline först. Sida vid sida kräver parning av block och mer arbete | `DiffSummary`, `FileChangeList`, `DiffView` (lägena inline och split) |
| **Konstellation i onboarding** (2.5) | Bra | Radiell layout med `Layout` (13). Linjer som ritas fram med `trim`. Noderna tänds efter vad första skanningen faktiskt hittar, så att bilden är sann. Därefter tre löften | `SourceConstellation`, `RadialLayout`, `PromiseList` |
| **Personlighet bara i lugnet** (2.6) | Bra | Regeln kan byggas in i API:t: `CalmState` tar bara lugna tillstånd. Varningar och fel använder en annan, saklig komponent. `ContentUnavailableView` behålls för tomma sökresultat | `CalmState` |
| **Widget** (2.7, senare) | Bara native | WidgetKit med samma komponenter. Ett widgettillägg kräver enligt min kännedom App Sandbox och får data via en App Group som appen skriver till (B, inte verifierat) | Återanvänder `PanelHero` |

**Slutsats (B):** Alla fyra karaktärskällor och alla mönster går att bära native. Tre av källorna går utan tillägg. Figur/maskot är den enda som kan motivera ett paket. Inget mönster motiverar en webbvy.

---

## 4. Rekommendation

### 4.1 Val

**A: Apples SwiftUI och AppKit som grund, med ett eget komponentlager.** Inga tredjepartsberoenden i etapp 1 tills panelens höjdändring är prövad.

`pick-ui-library`-mappning, alltså vad skillens webbval motsvarar här. Allt i högerkolumnen ligger utanför skillens lista.

| Uppgift | Skillens webbval | Skillori (native) |
| --- | --- | --- |
| Tillgängliga primitiver (dialog, popover, meny) | Base UI | SwiftUI-kontroller, `.sheet`, `.popover`, `Menu` |
| Kommandopalett | cmdk | Behövs inte i MVP. Senare: egen med `TextField`, `List` och `.onKeyPress` |
| Toasts | Sonner | `UserNotifications` och status i panelen. Inga toasts |
| Allmän rörelse | Motion | SwiftUI-animationer och fjädrar |
| Animerade siffror | NumberFlow | `.contentTransition(.numericText…)` |
| Syntaxmarkering | shiki | Ingen i första diffvyn. Senare Textual eller Highlightr, se 4.3 |
| Långa listor | Virtuoso | `List`/`Table` (virtualiserade via AppKit-tabeller, B) |
| Tillstånd | zustand | `@Observable` (används redan) |
| Varianter av stil | cva, clsx | `ButtonStyle`, `ViewModifier`, tokens |
| Ljust och mörkt läge | next-themes | Systemet |

### 4.2 Komponentlagret `SkilloriUI`

En mapp eller ett lokalt paket i appen. Bygg tokens först, så att den visuella riktning som ännu inte är vald kan läggas in utan att röra vyerna. Med baselinen är detta appens viktigaste del, inte ett tunt lager.

**Grund**

| Komponent | Innehåll |
| --- | --- |
| **Tokens** | Typroller, inte storlekar: `display`, `title`, `rowName`, `meta`, `path`, `hash`. Avstånd, radhöjd och täthet. Rörelse: `snappy`, `fold`, `none`, som läser reducerad rörelse. En semantisk statuspalett skild från accentfärgen |
| **`StatusBadge` v2** | Varje status har egen ikonform, egen text och färg. Läses i gråskala och av VoiceOver |
| **`FoldDisclosure`** | `DisclosureGroupStyle` för hälsokontroll, plugin-grupper och utfällda detaljer. Bär origamiidén där den betyder något |
| **`FoldedSurface`** | Ytan med veck och papperets två sidor. Används på ett eller två ställen |
| `PathText`, `RevisionChip` | Sökväg och hash eller revision i monospace. `PathText` finns redan och flyttas in |

**Panel**

| Komponent | Innehåll |
| --- | --- |
| **`PanelHero`** | Hjälteobjektet. Ett tillstånd i ord ("2 skills changed upstream", "All accounted for in 6 locations") och ett objekt, instrument, en figur eller ett stort tal som reagerar. Styrs av en enda `PanelState` (calm, changed, attention, checking, failed). Kan senare återanvändas i en widget |
| **`HealthCheckList` och `HealthCheckItem`** | Punkter med statusmarkör som fälls ut på plats med sin åtgärd. Ersätter dagens rutnät med fyra siffror |
| `NextActionButton`, `PanelButton`, `PanelSection` | Panelens egna kontroller med tryckläge |
| `FreshnessLabel` | "Last checked …" med inaktualitet, aldrig "Up to date" utan grund |

**Bibliotek och detaljvy**

| Komponent | Innehåll |
| --- | --- |
| `DistributionUnitRow` | Rad för plugin med antal skills, ägare och samlad status |
| **`ProvenanceTimeline` och `TimelineStep`** | Skillens resa från källa till installation och agentkopplingar. Ett okänt steg ritas som ett avbrott |
| **`RevisionScale`** och `TickRuler` | Instrumentskala för att bläddra mellan revisioner |

**Uppdatering och granskning**

| Komponent | Innehåll |
| --- | --- |
| `UpdateCard` | Upptäckt ändring skild från release notes |
| **`ReversibilityNote`** | Vad som går att ångra, i ett av tre lägen |
| **`DiffSummary`** | Filer, +/− rader, script och körbara filer markerade. Visas först |
| `FileChangeList` och `DiffView` | Fällbara filer med märkning (New, Script, Executable, Binary), "Mark as viewed", raddiff med `CollectionDifference`, lat rendering. Inline först, split senare. Samma vy i "Link source…" |

**Första start och lugna lägen**

| Komponent | Innehåll |
| --- | --- |
| **`SourceConstellation`** och `RadialLayout` | Agenterna runt Skillori, tända efter första skanningen |
| `PromiseList`, `OnboardingStep` | Tre löften, sedan en åtgärd |
| **`CalmState`** | Personlighet i lugna lägen. Tar bara lugna tillstånd, så att personlighet inte kan hamna i ett fel |

### 4.3 Paket på vänt, med villkor

| Paket | Lägg till när |
| --- | --- |
| MenuBarExtraAccess 1.3.1 | **Prova tidigt i etapp 1.** Om panelens höjd hoppar när hälsokontrollen fälls ut, eller om panelen måste öppnas via kod. Om paketet inte räcker är nästa steg eget `NSStatusItem` med `NSPanel` |
| KeyboardShortcuts 3.1.0 | Produktägaren vill ha ett globalt kortkommando för panelen |
| Textual 0.5.0 | Detaljvyn ska visa `SKILL.md` renderad, eller diffvyn ska få syntaxmarkering. Pinna exakt version |
| Rive 6.29.0 | Produktägaren väljer figur/maskot som karaktärskälla och en illustratör ska ge figuren flera tillstånd. Binärt XCFramework: granska ursprung, licens och notarisering innan det läggs till |

### 4.4 Hybridspåret

**Inte nu, och baselinen ändrar inte den bedömningen.** Alla mönster i baselinen är sammansatta vyer som native bär bra. En framtida widget kräver native. Det enda konkreta skälet för hybrid är fortfarande diffvyn: syntaxmarkering för många språk, diff på ordnivå och sida vid sida i stora filer, där webbens diffbibliotek är starkare än något native-paket (B). Att baselinen börjar med sammanfattningen minskar det skälet, eftersom den fulla diffen blir andrahandsvyn.

Kostnaderna står kvar:

- En `WKWebView`. SwiftUI:s `WebView` kräver macOS 26 (V).
- En npm-kedja och ett byggsteg i ett projekt som idag bara har Swift.
- Strikt CSP och escaping för opålitligt innehåll.
- Fokus och VoiceOver över gränsen mellan native och webb.
- Ett andra designspråk som måste efterlikna macOS, i två systemutseenden.
- En extra process. Minnet är inte mätt.

**Förslag:** Bygg sammanfattningen och inline-diffen native i etapp 2. Pröva hybrid bara om en mätning eller ett användartest visar att native inte räcker. Lägg då beslutet hos produktägaren som ett separat ADR.

### 4.5 Rörelse enligt `emil-design-eng`

Principerna översatta till Skillori. Värdena är startpunkter (B).

| Interaktion | Hur ofta | Beslut |
| --- | --- | --- |
| Öppna och stänga menyradspanelen | Många gånger per dag | Ingen egen animation. Systemets räcker |
| Piltangenter i listan, ⌘F, Esc, byte av filter | Mycket ofta, tangentbord | **Ingen animation** |
| Hover på rader och panelknappar | Mycket ofta | Omedelbart, som idag |
| Fälla ut en punkt i hälsokontrollen eller en plugin-grupp med musen | Tiotals per dag | 150–200 ms, ease-out eller fjäder utan studs. Panelens höjd följer i samma rörelse. Via tangentbord: ingen animation |
| Byta vald skill i detaljvyn | Ofta | Ingen glidning. Tidslinjen ritas inte fram varje gång. Högst en kort toning (≈120 ms) |
| `PanelHero` byter tillstånd | Ibland | Fjäder utan studs, ≤ 300 ms. Reducerad rörelse: toning |
| Dra i revisionsskalan | Ibland | Följer pekaren direkt. Snäpper med en kort fjäder och haptik. Piltangenter: hoppar utan animation |
| Vika fram ursprung och ändringar i detaljvyn | Ibland | Här får vikningen synas: ≤ 250 ms, ease-out, fäst vid kanten den viks från. Reducerad rörelse: toning |
| Räknare i panelen ändras | Sällan | `.contentTransition(.numericText…)` |
| Lugnt läge och figurens tomgång | Sällan sedd länge | Mycket diskret och långsam, pausad när panelen är stängd. Reducerad rörelse: stilla |
| Ny uppdatering hittad | Sällan | En diskret symbolrörelse, en gång |
| Tryck på egna knappar | Ofta | Tryckläge 100–160 ms, skala 0,97 eller tonad bakgrund |
| Onboarding med konstellationen | En gång | Får ha glädje: noder som tänds med 30–80 ms förskjutning och linjer som ritas fram. Kan hoppas över. Reducerad rörelse: slutbilden direkt |

Regler: aldrig studs i arbetsytor, aldrig skala från noll, utgång snabbare än ingång, ingen personlighet i varningar och fel, och ingen status som bara syns i en animation (namnbriefen §9).

### 4.6 Vad nuvarande kod säger om komponentlagret

Det här är observationer i den befintliga koden, inte ändringar.

| Före | Efter | Varför |
| --- | --- | --- |
| `MenuPanel` visar fyra `StatRow` i ett rutnät | `PanelHero` med ett tillstånd och en nästa handling, sedan `HealthCheckList` | Baselinen 2.1: panelen ska läsas på en sekund |
| `InstallationDetail` är ett `Form(.grouped)` med nyckel-värde-rader för källan | `ScrollView` med `ProvenanceTimeline` överst och fakta under | Baselinen 2.2: proveniens som resa, inte tabell |
| `StatusBadge` med färgerna `.green`, `.orange`, `.red`, `.blue` direkt i vyn | Semantiska statustokens i `SkilloriUI` | Ett ställe att ändra. `.blue` för "Managed" krockar med systemets standardaccent |
| `StatusBadge` med text på tonad kapsel, utan ikon | Ikon med egen form, text och färg | Status ska inte bero på färg. Formen läses också i små storlekar |
| `StatRow` markerar "Local changes" bara med orange | Lägg till en form, t.ex. ifylld ikon eller prick | Färgen är idag den enda signalen för att något behöver ses över |
| `PanelButton` har hoverbakgrund men inget tryckläge | `ButtonStyle` som läser `configuration.isPressed` | Knappar ska kännas mottagliga när de trycks |
| `LibraryView` visar 309 installationer i en platt `List` | `OutlineGroup` eller `Table` med `DisclosureTableRow`, egna skills först | Spikfynd 2: 280 av 309 ägs av plugins |
| Menyradsikonen skiljer "behöver uppmärksamhet" bara med fylld eller ofylld symbol | En tydligare formskillnad i mallbilden | Skillnaden är svag i 16 px. Väntar på vald symbol |

---

## 5. Risker och öppna frågor

### Risker

| Risk | Konsekvens | Hantering |
| --- | --- | --- |
| Liquid Glass kan inte väljas bort med SDK 27 (V) | Två utseenden: macOS 15 och 26+. Ett eget material kan krocka med glaset | Testa varje komponent på båda. Lägg identiteten i innehåll, typografi och rörelse, inte i fönsterytor |
| Panelens höjd när hälsokontrollen fälls ut (B, inte prövat) | Panelen hoppar i stället för att glida | Prova tidigt i etapp 1. MenuBarExtraAccess eller eget `NSPanel` |
| `MenuBarExtra` saknar API för att öppnas via kod (V, enligt MenuBarExtraAccess README). Fokus är inte manuellt kontrollerat (spiken) | Panelen kan kännas trög eller tappa fokus | Samma som ovan |
| Komponentlagret växer till ett tjugotal komponenter | Mer arbete än ett tunt lager, och stilar kan spridas i vyerna igen | Tokens först. Bygg i ordningen panel, detaljvy, diff. Bilder i ljust och mörkt läge och på macOS 15 och 26+ via `DebugSnapshots` |
| Egna komponenter (skala, tidslinje, hälsokontroll) saknar inbyggd tillgänglighet | Tangentbord och VoiceOver fungerar sämre än i `List` | Krav per komponent: fokus, piltangenter, en VoiceOver-etikett per steg, test med VoiceOver före varje leverans |
| Personlighet läcker in i varningar | Bryter baselinens princip 7 | Bygg in regeln i `CalmState`-API:t |
| Tidslinjen ser säkrare ut än evidensen | Bryter briefens krav på ärlig proveniens | Okända steg ritas som avbrott. "Linked by you" och "Inferred" får egna markörer |
| Agenternas logotyper i konstellationen | Varumärken som tillhör andra | Namn eller monogram tills användningsvillkoren är kontrollerade |
| Rive är ett binärt XCFramework (V) | Kod vi inte bygger själva i en notariserad app | Granska innan det läggs till. Bara om figur/maskot väljs |
| Diffvyn är egen kod | Prestanda för stora filer okänd. Sida vid sida är dyrast | Sammanfattning och inline först. Lat rendering, gränser enligt briefen §15, mätning med fixtures |
| Textual är före 1.0 (V) | API-ändringar | Pinna exakt version |
| STTextView är GPL eller kommersiell (V) | Licensbrott om det används av misstag | Avstå |
| Hybrid med opålitligt innehåll | Injektion i webbvyn | Bara via eget ADR med säkerhetsgranskning |

### Öppna frågor till produktägaren

1. **Karaktärskälla** (baselinen §1). Objekt/material, instrument/precision, figur/maskot eller typografi/redaktionellt? Figur/maskot är den enda som kan kräva ett paket (Rive). Objekt/material kräver mest designarbete mot glaset på macOS 26+. *Delvis besvarad 2026-11-11: produktägaren lutar mest mot instrument/precision. Enligt 3.3 bär native den källan mycket bra och utan tillägg. Rive behövs då inte.*
2. **Lägsta macOS-version.** Ska den höjas från 15 till 26, så att appen bara har ett systemutseende och kan använda Liquid Glass och SF Symbols "Draw" fullt ut? Beslut 0003 tillåter en höjning om något centralt kräver det.
3. **Globalt kortkommando** för panelen? Det avgör om KeyboardShortcuts behövs.
4. **Diffen i etapp 2.** Räcker sammanfattning och inline, eller krävs sida vid sida och syntaxmarkering? Det avgör om Textual eller Highlightr behövs och om hybrid alls blir en fråga.
5. **Renderad `SKILL.md`** i detaljvyn, eller bara metadata och rå text?
6. **Eget typsnitt** eller SF? Särskilt aktuellt om typografi/redaktionellt väljs. Ett inbäddat typsnitt kräver en licens för inbäddning i appen.
7. **Agenternas logotyper** i konstellationen, eller bara namn?
8. **Widget** på skrivbordet och i Notification Center. Senare mål eller inte alls? Ett widgettillägg påverkar sandlådefrågan i beslut 0002.

---

## Källor

Kontrollerade 11 november 2026.

- GitHub API: release, licens, arkivstatus och `Package.swift` för paketen i tabell 2.2, inklusive Rive och Lottie.
- npm-registret: `@base-ui/react`, `motion`, `shiki`, `@pierre/diffs`, `react`, `cmdk`, `sonner`.
- SDK: `MacOSX27.2.sdk` i Xcode 27.2 (build 27B52), `SwiftUI`, `SwiftUICore`, `Symbols`, `_WebKit_SwiftUI` och `ServiceManagement`.
- [Apple Developer Forums: Clarification on the planned removal of UIDesignRequiresCompatibility](https://developer.apple.com/forums/thread/832543)
- [Apple Developer Forums: UIDesignRequiresCompatibility and iOS 27](https://developer.apple.com/forums/thread/832710)
- [Mobbin-baseline](mobbin-baseline-2026-11-11.md), med länkar till referenserna.
- Skillerna `pick-ui-library` (`~/.agents/skills/pick-ui-library/SKILL.md`) och `emil-design-eng`.
