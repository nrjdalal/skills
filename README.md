# skills

A [Claude Code](https://claude.com/claude-code) plugin marketplace. Skills follow the
[Agent Skills](https://agentskills.io) open standard.

## Install

```
/plugin marketplace add nrjdalal/skills
/plugin install video-research@nrjdalal-skills
```

Update later with `/plugin marketplace update nrjdalal-skills`.

> The marketplace is named `nrjdalal-skills`. Names like `agent-skills` and
> `anthropic-plugins` are reserved for Anthropic's official marketplaces — a
> third-party marketplace using one is rejected as untrusted.

### Without the marketplace

Any skill here is a plain directory, so you can copy one straight in:

```bash
git clone https://github.com/nrjdalal/skills
cp -r skills/plugins/video-research/skills/transcribe ~/.claude/skills/
```

Use `.claude/skills/` inside a repo instead to scope it to one project.

## Plugins

| Plugin | Skills | What it does |
| :-- | :-- | :-- |
| [`video-research`](./plugins/video-research) | `/transcribe` | Transcribe YouTube videos locally on Apple Silicon with yt-dlp and Parakeet |

## Layout

```
.claude-plugin/marketplace.json          catalog of plugins
plugins/
  video-research/
    .claude-plugin/plugin.json           plugin manifest
    skills/
      transcribe/SKILL.md                the skill itself
```

Skills live in a plugin's `skills/` directory, one directory per skill, each with a
`SKILL.md`. The directory name becomes the command, so `/transcribe` here.

## Adding a skill

1. `plugins/<plugin>/skills/<skill>/SKILL.md` with `name` and `description` frontmatter.
   The `description` is what Claude matches on, so say *when to reach for this*, not
   just what it is.
2. Add the plugin to `.claude-plugin/marketplace.json` if it's new.
3. `claude plugin validate .` before pushing.

Skills can also carry `reference.md`, `scripts/`, `templates/` and `assets/` alongside
`SKILL.md` when they need supporting files.

## Licence

MIT
