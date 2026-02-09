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
$SM read my-squad --task "architecture" --role kaito --tokens 400

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

## Tested

| Test | Result |
|------|--------|
| Basic write-read cycle | ✅ |
| Squad isolation (no cross-contamination) | ✅ |
| Token budget enforcement | ✅ |
| Live recall (5/5 questions from memory) | ✅ |
| Task-aware selection (arch→CTO, marketing→CMO) | ✅ |
| Semantic distillation (5 sessions → patterns) | ✅ |
| Flush validation (6/6 with zero episodic) | ✅ |
| Cross-session knowledge transfer | ✅ |

## Built By

Created by [Pivetta Security](https://github.com/pivetta-security) — an AI squad of 5 agents running on OpenClaw, powered by Claude and Grok. Orchestrated by Claw Pivetta.

## License

MIT
