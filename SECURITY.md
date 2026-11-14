# Security

Skillori reads folders that contain content from other people, and it can start `npx skills update` when you ask it to. Problems in either area are taken seriously.

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead: **Security → Report a vulnerability** on this repository. You'll get an answer within a week.

Examples of what counts:

- a skill folder that makes Skillori run code, follow a path outside the folders it reads, or hang,
- a way to make the update command run something other than `npx skills update` for a plain skill name,
- data leaving the Mac beyond the repository name sent by the upstream check.

## Supported versions

Only the latest commit on `main` is supported while Skillori is at 0.x.
