# skills

Skills for [Claude Code](https://claude.com/claude-code), packaged as an installable
plugin. Follows the [Agent Skills](https://agentskills.io) open standard.

## Install

```
/plugin marketplace add nrjdalal/skills
/plugin install nrjdalal-skills@nrjdalal
```

Update later with `/plugin marketplace update nrjdalal`.

### Without the plugin

Every skill is a plain directory, so you can copy one straight in:

```bash
git clone https://github.com/nrjdalal/skills
cp -r skills/skills/transcribe ~/.claude/skills/
```

Use `.claude/skills/` inside a repo instead to scope it to one project.

## Skills

| Command | What it does |
| :-- | :-- |
| [`/transcribe`](./skills/transcribe) | Transcribe YouTube videos locally on Apple Silicon with yt-dlp and Parakeet |

## Layout

```
.claude-plugin/
  marketplace.json     catalog — lists this repo as one plugin
  plugin.json          plugin manifest
skills/
  transcribe/
    SKILL.md           the skill
```

The repo root *is* the plugin: `marketplace.json` points its one entry at `"./"`.
Skills sit in `skills/<name>/`, one directory each, and the directory name becomes
the command.

Skills can also carry `reference.md`, `scripts/`, `templates/`, `assets/` or `agents/`
alongside `SKILL.md` when they need supporting files.

## Adding a skill

1. Create `skills/<name>/SKILL.md` with `name` and `description` frontmatter.
2. Run `claude plugin validate .`
3. Commit and push. Users pick it up with `/plugin marketplace update nrjdalal`.

Write the `description` as *what it does, then when to reach for it* — Claude matches
on this text, so include the phrases someone would actually type:

```markdown
---
name: transcribe
description: Transcribe YouTube videos locally on Apple Silicon with yt-dlp and
  Parakeet. Use when the user pastes a YouTube or channel link, asks to transcribe
  or summarise a video, or wants analysis across several videos.
---
```

Useful optional frontmatter: `disable-model-invocation: true` keeps a skill off
Claude's automatic radar so it only runs when you type `/name`, and `argument-hint`
shows expected arguments during autocomplete.

### Grouping into categories

Once there are enough skills to want folders, nest them as
`skills/<category>/<name>/SKILL.md` and list each skill path explicitly in
`plugin.json`:

```json
"skills": ["./skills/media/transcribe", "./skills/engineering/review"]
```

The default scan only walks `skills/<name>/`, so a nested skill is invisible without
that array.

## Naming

The marketplace is `nrjdalal` and the plugin is `nrjdalal-skills`, which is why the
install line reads `nrjdalal-skills@nrjdalal`. Names like `agent-skills` and
`anthropic-plugins` are reserved for Anthropic's official marketplaces — a
third-party marketplace using one is rejected as untrusted.

## Licence

MIT
