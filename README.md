# Skillori

> Know your skills. See what changed.

Skillori is a small macOS menu bar app that shows which AI agent skills are on your Mac, no matter which agent they belong to or how they were installed. It tells you where each skill came from, and whether its source has changed since you installed it.

![The Skillori menu bar panel in seven states: in sync, updates, no contact, on this Mac, dark mode and first start](docs/images/panel-states.png)

## What it does

- **Finds your skills.** Reads the skill folders of Claude Code, Cursor, Codex, Gemini CLI, Antigravity, GitHub Copilot, OpenCode, Amp, Kiro, Factory Droid, Devin Desktop and goose, including the shared `~/.agents/skills` folder and plugin caches. The same skill linked into five agents shows up once.
- **Knows where they came from.** Reads the lockfile written by `npx skills` and the plugin metadata of Claude Code, Cursor and Codex. Skills with no known source can be linked to a GitHub repository by hand.
- **Tells you what changed.** When you turn it on, it asks GitHub whether a skill's source folder has changed, by comparing git tree hashes. No account, no token.
- **Stays out of the way.** Lives in the menu bar. Skills you wrote yourself are listed first; the hundreds managed by plugins are grouped under the app that manages them.

## Principles

- Skill content is treated as untrusted data. Skillori never runs a script from a skill, neither while reading nor while comparing.
- Nothing is uploaded. The only network request is the optional upstream check, and it carries the repository name and nothing else.
- Skillori doesn't write to your skill folders. An update only happens when you press **Update**, and then it's `npx skills update` that writes the files.

## Status

Early beta. Version 0.1.0 can be downloaded from [skillori.app](https://skillori.app), notarized by Apple, and keeps itself up to date from then on. Reading the inventory works well; update checks work for skills installed with `npx skills` and for skills you link by hand. What each version brought is on the [changelog](https://skillori.app/changelog/), and what's next is in the [backlog](docs/backlog.md) (in Swedish).

## Building

Requirements: macOS 15 or later, Xcode with the Swift 6 toolchain (developed with Xcode 27), and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodebuild -downloadComponent MetalToolchain   # once; the build compiles a Metal shader
xcodegen generate
open Skillori.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project Skillori.xcodeproj -scheme Skillori -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Skillori.app
```

The `.xcodeproj` is generated from [`project.yml`](project.yml) and is not committed. Run `xcodegen generate` again after adding or removing files.

### Signing

Out of the box the app gets an ad-hoc signature, so it builds on any Mac without an Apple developer account. To sign with your own Developer ID, copy [`Config/Signing.local.xcconfig.example`](Config/Signing.local.xcconfig.example) to `Config/Signing.local.xcconfig` and fill in your team ID. That file is ignored by git. [`scripts/notarize.sh`](scripts/notarize.sh) builds, signs, notarizes and staples a release; its header lists what it needs.

### Tests

```bash
swift test --package-path Packages/SkilloriCore
```

Tests build their fixtures in temporary folders and never touch real installations.

## Releasing

A release is one command, run from a Mac that can sign as Skillori's team:

```bash
sh scripts/release.sh 0.2.0 "One or two sentences in English on what is new."
```

[`scripts/release.sh`](scripts/release.sh) does the following, and stops at the first step that fails:

1. Bumps the version in `project.yml` and builds a Release app signed with Developer ID, Sparkle's helpers included.
2. Has Apple notarize the app and a `.dmg` around it, staples both and checks them with Gatekeeper.
3. Signs the `.dmg` with Skillori's EdDSA key for Sparkle.
4. Writes the site: the version on the launch page, a new row on top of the changelog, the appcast installed copies update from, and the sitemap (see below). Nothing on the site changes unless every step before it succeeded.
5. Copies `Skillori.dmg` into Dropbox under the same name, which keeps its link, and waits until Dropbox serves the new file.

Then review the diff and commit, tag and push, as the script prints at the end:

```bash
git add project.yml site/index.html site/changelog/index.html site/appcast.xml site/sitemap.xml scripts/release.conf site/api/download.mjs
git commit -m "Release 0.2.0"
git tag v0.2.0
git push origin main --tags
sh scripts/release.sh --check   # does skillori.app/download lead to the new file?
```

The push publishes the site on Vercel, and with it the appcast, so push soon after Dropbox has the file: until then the old appcast's signature doesn't match the new `.dmg`.

What it needs, once per Mac: `Config/Signing.local.xcconfig` (see [Signing](#signing)), `scripts/notarize.conf.local` with the notarization credentials (see [`scripts/notarize.sh`](scripts/notarize.sh)), and Sparkle's private key in the login keychain (`sh scripts/release.sh --keys` makes one; there is only one, so import the saved copy rather than making a new key on a second Mac). Neither file nor the key is ever committed. Shared settings are in [`scripts/release.conf`](scripts/release.conf).

### Downloads

Every download button points at `skillori.app/download`. A small Vercel function ([`site/api/download.mjs`](site/api/download.mjs)) adds one to a counter and redirects to `Skillori.dmg` in Dropbox. The counter keeps only numbers, a total and one per day, with nothing about who downloaded. Since the file is replaced under the same name, the link never changes and the buttons never need editing. Should the file ever be deleted and uploaded again, it gets a new link: copy it in Finder (Copy Dropbox link) and run `sh scripts/release.sh --link "<link>"`, which writes it into both `release.conf` and the function.

### Sitemap

Each release rebuilds [`site/sitemap.xml`](site/sitemap.xml) from the pages under `site/`, so a new page is listed without anyone remembering to:

- Every `.html` file is listed at the address Vercel serves it from: `guide/index.html` and `guide.html` both become `/guide/`. `api/` and `fonts/` are skipped.
- A page with `<meta name="robots" content="noindex">` stays out.
- The launch page and the changelog, which change with every release, get the release date. Every other page keeps the date it already had, so search engines don't think it changed.

The sitemap is submitted to Google Search Console under the domain property for skillori.app, which reads it again by itself. [`site/robots.txt`](site/robots.txt) points to it and keeps crawlers away from `/download/`, so they aren't counted as downloads. A page added between releases is listed with the next release. To list it sooner, add a line for it to `site/sitemap.xml` by hand; the next release keeps that line's date.

## Project layout

| Path | What's there |
| --- | --- |
| `App/Skillori/` | The app: menu bar panel, library window, detail view, settings |
| `Packages/SkilloriCore/` | Discovery, adapter rules per agent, `SKILL.md` parsing, git tree hashing, lockfile reading, upstream checks. No UI. |
| `Packages/SkilloriCore/Sources/SkilloriProbe/` | `skillori-probe`, a command line tool that prints the inventory for the current user |
| `Packages/SkilloriUI/` | Design tokens, typography, components and the `LightField` Metal shader |
| `site/` | skillori.app on Vercel: launch page, changelog, appcast, sitemap and the download counter |
| `scripts/` | The release script and its settings, notarization |
| `docs/` | Product brief, research, architecture decisions and design history. See [docs/README.md](docs/README.md). |

The docs are written in Swedish, the code and the app in English.

## Contributing

Forks are welcome, and so are issues and pull requests. See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security problem, see [SECURITY.md](SECURITY.md).

## License

The code is released under the [MIT License](LICENSE).

The license covers the code, not the name or the brand. "Skillori" and the Skillori mark are not licensed for use in forks: if you distribute your own version, give it its own name, icon and bundle identifier.

Some files come from others and keep their own terms:

- Inter and Geist Mono are under the SIL Open Font License 1.1 (see [`Packages/SkilloriUI/Sources/SkilloriUI/Resources/Fonts/`](Packages/SkilloriUI/Sources/SkilloriUI/Resources/Fonts/)).
- The agent logos in [`App/Skillori/AgentLogos/`](App/Skillori/AgentLogos/) are trademarks of their owners and are used only to identify each agent.
