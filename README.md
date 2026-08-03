# agent-skills

Skills for [Claude Code](https://claude.com/claude-code). Each directory is one
skill: a `SKILL.md` the agent reads when the task matches, plus any scripts it needs.

## Skills

| Skill | What it does |
|---|---|
| [`video-research`](./video-research) | Transcribe and analyse YouTube videos locally on Apple Silicon — no API keys, no audio leaving the machine |

## Installing

Clone into your skills directory:

```bash
git clone https://github.com/nrjdalal/agent-skills ~/.claude/skills-src
ln -s ~/.claude/skills-src/video-research ~/.claude/skills/video-research
```

Or copy a single skill in:

```bash
cp -r video-research ~/.claude/skills/
```

Project-scoped instead of global? Use `.claude/skills/` inside the repo.

## Writing skills

A skill is a folder with a `SKILL.md` whose frontmatter carries a `name` and a
`description`. The description is what the agent matches against, so it should say
*when to reach for this*, not just what it is.

```markdown
---
name: my-skill
description: Does X. Use when the user asks for Y.
---

# My skill

Instructions the agent follows.
```

The useful content is rarely the happy path — it's the failure modes, the defaults
worth having, and the measurements that justify them.

## Licence

MIT
