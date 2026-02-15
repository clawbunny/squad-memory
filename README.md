# 🧠 Squad Memory

**Persistent memory for OpenClaw sub-agent squads.**

Sub-agents are stateless — they wake up fresh every session with zero recall. Squad Memory gives them three layers of persistent knowledge:

| Layer | What | Lifespan | Flushable? |
|-------|------|----------|------------|
| **Process** | How you work, standards, values | Permanent | Never |
| **Program** | Project expertise, role patterns | Per-project | Optional |
| **Episodic** | Session logs, recent context | Rolling | Yes |

## Why?

Without persistent memory, your orchestrator spends thousands of tokens re-explaining context every spawn. Sub-agents repeat mistakes. They can't learn from experience.

With Squad Memory:
- **50% fewer context tokens** per spawn
- **Role-tagged learnings** compound across sessions
- **Task-aware selection** loads only relevant memories
- **Flush controls** let you start fresh without losing expertise
- **Dynamic role discovery** adapts to your squad structure

## Install

```bash
# Clone into your OpenClaw skills directory
git clone https://github.com/clawbunny/squad-memory.git ~/.openclaw/skills/squad-memory

# Initialize process memory
mkdir -p ~/.openclaw/workspace/memory/squads/_process
cp ~/.openclaw/skills/squad-memory/process-template.md ~/.openclaw/workspace/memory/squads/_process/standards.md
```

## Usage

```bash
SM="~/.openclaw/skills/squad-memory/squad-memory.sh"

# Write after a spawn completes
echo "## Session summary..." | $SM write my-squad -

# Read before spawning (inject into task prompt)
$SM read my-squad --tokens 500

# Smart selection for architecture task
$SM read my-squad --task "architecture" --role architect --tokens 400

# Distill patterns from session history
$SM distill my-squad

# Start fresh (archives first)
$SM flush my-squad --keep-semantic
```

## How It Works

```
Before Spawn:
  read → Process + Program + Episodic → inject into task prompt (500 tokens)

After Spawn:
  Extract "Session Memory" → write → role-tagged learnings accumulate

Every 3 Sessions:
  Auto-distill → episodic patterns promoted to semantic/program memory
```

## Example Role Tags

Use any role names that fit your squad. The system dynamically discovers them:

```markdown
## Session Memory
- [ARCHITECT] Learned to validate schema before migration
- [ANALYST] Market research shows 60% prefer feature X
- [COORDINATOR] Sprint planning works better async for distributed teams
- [ALL] Always test edge cases before deployment
```

## Security

**Version 2.0** includes comprehensive security hardening:
- ✅ Path traversal protection (squad IDs validated)
- ✅ Command injection prevention (all expansions quoted)
- ✅ Race condition mitigation (mktemp for temp files)
- ✅ Input validation (numeric parameters verified)
- ✅ Safe glob handling (no unsafe wildcards)
- ✅ ShellCheck compliant

## Tested

| Test | Result |
|------|--------|
| Basic write-read cycle | ✅ |
| Squad isolation (no cross-contamination) | ✅ |
| Token budget enforcement | ✅ |
| Live recall (5/5 questions from memory) | ✅ |
| Task-aware selection | ✅ |
| Semantic distillation (5 sessions → patterns) | ✅ |
| Flush validation (6/6 with zero episodic) | ✅ |
| Cross-session knowledge transfer | ✅ |
| Path traversal prevention | ✅ |
| Dynamic role discovery | ✅ |

## License

MIT

## Links

- **GitHub**: https://github.com/clawbunny/squad-memory
- **ClawHub**: Coming soon
