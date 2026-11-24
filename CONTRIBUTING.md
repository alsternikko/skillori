# Contributing

Thanks for taking a look. Skillori is a small project with one maintainer, so here's how to make the most of your time.

## Forks

Fork freely; that's what the MIT License is for. If you distribute your own build, give it its own name, icon and bundle identifier (see [Signing](README.md#signing)), so nobody confuses it with Skillori.

## Issues

Bug reports are most useful with:

- your macOS version and which agents you use,
- what Skillori showed, and what you expected,
- the output of `swift run --package-path Packages/SkilloriCore skillori-probe` if the inventory looks wrong. Read it before you paste it: it lists folder paths and skill names from your Mac.

## Pull requests

Open an issue first for anything bigger than a small fix, so we can agree on the direction before you spend time on it. Then:

1. Build with `xcodegen generate` and Xcode, as described in the [README](README.md#building).
2. Run `swift test --package-path Packages/SkilloriCore`. Add tests for new discovery or provenance rules.
3. Keep the pull request to one change.

## Ground rules in the code

- **Skill content is untrusted data.** Nothing from a skill folder is ever executed, evaluated or passed to a shell while reading or comparing. Names passed to external tools go as arguments, never as a shell string.
- **Never change a real installation.** Tests build fixtures in temporary folders.
- **Nothing leaves the Mac** except what the user can turn off: the daily update check to skillori.app and the source checks, which name a repository and say nothing about the user. The [README](README.md#principles) lists everything a source check can ask.
- **Adapter rules follow documentation.** A new agent or folder should point to the agent's own docs. [`docs/research/kompatibilitetsmatris.md`](docs/research/kompatibilitetsmatris.md) lists the sources used so far.
- The app's UI text, code identifiers and comments are in English. The working documents in `docs/` are in Swedish; you don't have to write Swedish to contribute.
