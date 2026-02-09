# Squad Memory — Persistent Memory for OpenClaw Sub-Agents

Give your AI sub-agent squads persistent memory across sessions. Sub-agents wake up stateless — this skill gives them institutional knowledge.

## What It Does

Three-layer memory architecture:
- **Process Memory** — Permanent standards (how you work, what the human values). Never flushed. Applies to all programs.
- **Program Memory** — Project-specific expertise distilled from sessions. Survives episodic flush.
- **Episodic Memory** — Raw session logs with role-tagged learnings. Flushable per project.

## Quick Start

### 1. Initialize process memory
Copy and customize the template:
```bash
mkdir -p ~/.openclaw/workspace/memory/squads/_process
cp process-template.md ~/.openclaw/workspace/memory/squads/_process/standards.md
# Edit standards.md with your team's permanent standards
```

### 2. Write session memory
After a sub-agent spawn completes, capture its learnings:
```bash
echo "## Session summary...
- [ROLE] Learning tagged by role" | ./squad-memory.sh write my-squad -
```

### 3. Read memory before spawning
```bash
./squad-memory.sh read my-squad --tokens 500
```
Prepend the output to your spawn task prompt.

### 4. Smart selection
```bash
# Task-aware — loads only relevant memories
./squad-memory.sh read my-squad --task "architecture design" --tokens 500

# Role-filtered — for solo-agent spawns
./squad-memory.sh read my-squad --role kaito --tokens 300

# Combined
./squad-memory.sh read my-squad --role kaito --task "native host" --tokens 400
```

## Commands

| Command | Description |
|---------|-------------|
| `write <squad> <file\|->` | Write session memory |
| `read <squad> [options]` | Read memory (all 3 layers) |
| `distill <squad>` | Extract semantic patterns from episodic |
| `compress <squad> [--days N]` | Compress old sessions |
| `flush <squad>` | Full wipe (archives first) |
| `flush <squad> --keep-semantic` | Wipe sessions, keep expertise |
| `list <squad>` | Show squad memory status |
| `stats` | Overview of all squads |

## Read Options

| Option | Description | Default |
|--------|-------------|---------|
| `--tokens N` | Total token budget | 500 |
| `--limit N` | Number of recent sessions | 3 |
| `--role ROLE` | Filter by agent role | all |
| `--task "desc"` | Task-aware relevance selection | none |

## Memory Format

Sub-agents write learnings with role tags:
```markdown
## Session Memory
- [VERA] Business insight
- [KAITO] Technical learning
- [ALL] Cross-cutting pattern
```

Role names are customizable — use whatever roles your squad has.

## Orchestrator Protocol

1. **Before spawn:** `squad-memory.sh read squad --tokens 500` → prepend to task prompt
2. **In task prompt:** Add instruction: "At END of response, include `## Session Memory` with `[ROLE]` tagged learnings"
3. **After spawn:** Extract Session Memory section → `squad-memory.sh write squad -`

## Storage

```
~/.openclaw/workspace/memory/squads/
├── _process/              # Permanent (never flushed)
│   └── standards.md       # How you work, what human values
├── {squad-id}/            # Per-squad
│   ├── history.md         # Episodic (session logs)
│   ├── semantic.md        # Program (distilled expertise)
│   └── meta.json          # Health metrics
```

## Auto-Behaviors

- **Auto-distill:** Semantic memory extracted every 3 sessions
- **Auto-archive:** Flush and compress archive before destructive ops
- **Token budget split:** 150 process + 200 program + 150 episodic = 500

## Requirements

- Bash 4.0+ (macOS: `brew install bash`)
- OpenClaw with sub-agent support (`sessions_spawn`)
