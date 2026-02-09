#!/usr/bin/env bash
# Squad Memory System — Phase 2
# Usage:
#   squad-memory.sh write    <squad-id> <summary-file|->
#   squad-memory.sh read     <squad-id> [--role ROLE] [--limit N] [--tokens N] [--task "desc"]
#   squad-memory.sh list     <squad-id>
#   squad-memory.sh stats    [squad-id]
#   squad-memory.sh distill  <squad-id>          # Extract semantic memory from episodic
#   squad-memory.sh compress <squad-id> [--days N]  # Compress old sessions

set -euo pipefail

MEMORY_ROOT="${OPENCLAW_WORKSPACE:-$HOME/.openclaw/workspace}/memory/squads"
DEFAULT_LIMIT=3
DEFAULT_TOKEN_BUDGET=500
SEMANTIC_BUDGET=300
EPISODIC_BUDGET=200
CHARS_PER_TOKEN=4

cmd="${1:-help}"
squad_id="${2:-}"

# --- Helpers ---

die() { echo "ERROR: $1" >&2; exit 1; }

ensure_squad_dir() {
  local dir="$MEMORY_ROOT/$squad_id"
  mkdir -p "$dir"
  echo "$dir"
}

estimate_tokens() {
  local chars=${#1}
  echo $(( chars / CHARS_PER_TOKEN ))
}

truncate_to_tokens() {
  local text="$1"
  local max_tokens="$2"
  local max_chars=$(( max_tokens * CHARS_PER_TOKEN ))
  if [ ${#text} -le $max_chars ]; then
    echo "$text"
  else
    echo "${text:0:$max_chars}..."
  fi
}

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# --- Commands ---

cmd_write() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh write <squad-id> <summary-file|->"
  local summary_file="${3:-}"
  [ -z "$summary_file" ] && die "Provide a session summary file or use - for stdin"

  local dir; dir=$(ensure_squad_dir)
  local history="$dir/history.md"

  local content
  if [ "$summary_file" = "-" ]; then content=$(cat)
  else [ -f "$summary_file" ] || die "File not found: $summary_file"; content=$(cat "$summary_file"); fi

  { echo ""; echo "---"; echo "**Recorded:** $(timestamp)"; echo ""; echo "$content"; } >> "$history"

  # Update meta
  local meta="$dir/meta.json"
  local count=0
  [ -f "$meta" ] && count=$(grep -o '"sessionCount":[0-9]*' "$meta" 2>/dev/null | grep -o '[0-9]*' || echo 0)
  count=$((count + 1))

  local sem_exists="false"
  [ -f "$dir/semantic.md" ] && sem_exists="true"

  cat > "$meta" << METAEOF
{
  "squadId": "$squad_id",
  "sessionCount": $count,
  "lastUpdated": "$(timestamp)",
  "hasSemanticMemory": $sem_exists,
  "historyFile": "history.md"
}
METAEOF

  echo "OK: Memory written for squad '$squad_id' (session #$count)"

  # Auto-distill every 3 sessions
  if [ $((count % 3)) -eq 0 ] && [ $count -ge 3 ]; then
    echo "Auto-distilling semantic memory (every 3 sessions)..."
    cmd_distill
  fi
}

cmd_read() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh read <squad-id> [options]"

  local dir="$MEMORY_ROOT/$squad_id"
  local history="$dir/history.md"
  local semantic="$dir/semantic.md"

  local role="" limit=$DEFAULT_LIMIT token_budget=$DEFAULT_TOKEN_BUDGET task=""
  shift 2

  while [ $# -gt 0 ]; do
    case "$1" in
      --role) role="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --tokens) token_budget="$2"; shift 2 ;;
      --task) task="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  local output=""

  # --- Process Memory (always loaded first, cross-program, never flushed) ---
  local process_dir="$MEMORY_ROOT/_process"
  if [ -f "$process_dir/standards.md" ]; then
    local process_content
    process_content=$(truncate_to_tokens "$(cat "$process_dir/standards.md")" 150)
    output="## Process Memory (permanent — applies to ALL programs)"$'\n'"$process_content"$'\n'$'\n'
    # Reduce other budgets to fit within total
    SEMANTIC_BUDGET=200
    EPISODIC_BUDGET=150
  fi

  # --- Semantic Memory (program-specific expertise) ---
  if [ -f "$semantic" ]; then
    local sem_budget=$SEMANTIC_BUDGET
    [ $token_budget -lt 500 ] && sem_budget=$((token_budget / 2))

    local sem_content
    sem_content=$(cat "$semantic")

    # Role filter on semantic
    if [ -n "$role" ]; then
      local role_upper; role_upper=$(echo "$role" | tr '[:lower:]' '[:upper:]')
      sem_content=$(echo "$sem_content" | grep -E "(^#|^$|^\*\*|\[$role_upper\]|\[ALL\])" || echo "$sem_content")
    fi

    # Task relevance filter on semantic
    if [ -n "$task" ]; then
      local task_lower; task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')
      # Extract keywords (words >3 chars)
      local keywords; keywords=$(echo "$task_lower" | tr ' ' '\n' | awk 'length>3' | head -10)
      local relevant_lines=""
      local line
      while IFS= read -r line; do
        local line_lower; line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        local matched=0
        for kw in $keywords; do
          if echo "$line_lower" | grep -q "$kw" 2>/dev/null; then matched=1; break; fi
        done
        # Keep headers, blank lines, and matched lines
        if [ $matched -eq 1 ] || echo "$line" | grep -qE '^(#|$|\*\*)'; then
          relevant_lines="${relevant_lines}${line}"$'\n'
        fi
      done <<< "$sem_content"
      [ -n "$relevant_lines" ] && sem_content="$relevant_lines"
    fi

    sem_content=$(truncate_to_tokens "$sem_content" "$sem_budget")
    output="${output}## Program Memory (project-specific expertise)"$'\n'"$sem_content"$'\n'$'\n'
  fi

  # --- Episodic Memory ---
  if [ -f "$history" ]; then
    local epi_budget=$EPISODIC_BUDGET
    [ ! -f "$semantic" ] && epi_budget=$token_budget  # No semantic = full budget to episodic
    [ $token_budget -lt 500 ] && epi_budget=$((token_budget / 2))

    local sessions
    sessions=$(awk 'BEGIN{RS="---"; ORS="---"} {a[NR]=$0} END{start=NR-'"$limit"'+1; if(start<1)start=1; for(i=start;i<=NR;i++) print a[i]}' "$history")

    if [ -n "$role" ]; then
      local role_upper; role_upper=$(echo "$role" | tr '[:lower:]' '[:upper:]')
      sessions=$(echo "$sessions" | grep -E "(^##|^Task:|^Outcome:|^\*\*Recorded|^---|^\s*$|\[$role_upper\]|\[ALL\])" || echo "$sessions")
    fi

    # Task relevance scoring for episodic
    if [ -n "$task" ]; then
      local task_lower; task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')
      local keywords; keywords=$(echo "$task_lower" | tr ' ' '\n' | awk 'length>3' | head -10)
      # Score each session block, keep highest scoring ones
      # Simple: filter learning lines that match task keywords
      local filtered=""
      local line
      while IFS= read -r line; do
        local line_lower; line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        local matched=0
        for kw in $keywords; do
          if echo "$line_lower" | grep -q "$kw" 2>/dev/null; then matched=1; break; fi
        done
        if [ $matched -eq 1 ] || echo "$line" | grep -qE '^(##|---|\*\*|Task:|Outcome:|$)'; then
          filtered="${filtered}${line}"$'\n'
        fi
      done <<< "$sessions"
      [ -n "$filtered" ] && sessions="$filtered"
    fi

    sessions=$(truncate_to_tokens "$sessions" "$epi_budget")
    output="${output}## Recent Sessions (last $limit)"$'\n'"$sessions"
  fi

  if [ -z "$output" ]; then
    echo "# No memory found for squad '$squad_id'"
    exit 0
  fi

  echo "# Squad Memory: $squad_id"
  [ -n "$role" ] && echo "## Filtered for role: $role"
  [ -n "$task" ] && echo "## Task-relevant selection: $task"
  echo ""
  echo "$output"
}

cmd_distill() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh distill <squad-id>"

  local dir="$MEMORY_ROOT/$squad_id"
  local history="$dir/history.md"
  [ -f "$history" ] || die "No history found for squad '$squad_id'"

  local semantic="$dir/semantic.md"

  # Extract all learning lines
  local all_learnings
  all_learnings=$(grep -E '^\- \[' "$history" || true)
  [ -z "$all_learnings" ] && { echo "No learnings to distill."; return; }

  # Count occurrences of similar themes
  # Group by role
  local roles="VERA KAITO RENA OMAR LUNA ALL"

  {
    echo "# Semantic Memory: $squad_id"
    echo "**Distilled:** $(timestamp)"
    echo "**Sessions analyzed:** $(grep -c '^---' "$history" 2>/dev/null || echo 0)"
    echo ""

    for r in $roles; do
      local role_learnings
      role_learnings=$(echo "$all_learnings" | grep "\[$r\]" || true)
      [ -z "$role_learnings" ] && continue

      # Deduplicate — keep unique learnings (by first 40 chars after role tag)
      local seen="" deduplicated=""
      while IFS= read -r line; do
        local key; key=$(echo "$line" | sed "s/.*\[$r\] //" | cut -c1-40 | tr '[:upper:]' '[:lower:]')
        if ! echo "$seen" | grep -qF "$key" 2>/dev/null; then
          seen="${seen}${key}|"
          deduplicated="${deduplicated}${line}"$'\n'
        fi
      done <<< "$role_learnings"

      if [ -n "$deduplicated" ]; then
        case "$r" in
          VERA)  echo "### CEO Patterns (Vera)" ;;
          KAITO) echo "### CTO Patterns (Kaito)" ;;
          RENA)  echo "### CSO Patterns (Rena)" ;;
          OMAR)  echo "### CPO Patterns (Omar)" ;;
          LUNA)  echo "### CMO Patterns (Luna)" ;;
          ALL)   echo "### Cross-Cutting Patterns" ;;
        esac
        echo "$deduplicated"
      fi
    done

    # Extract success/failure patterns
    echo "### Track Record"
    local successes; successes=$(grep -c "SUCCESS" "$history" 2>/dev/null || echo 0)
    local failures; failures=$(grep -c "FAILURE" "$history" 2>/dev/null || echo 0)
    echo "- Sessions: $((successes + failures)) | Success: $successes | Failure: $failures"
    echo ""
  } > "$semantic"

  local sem_size; sem_size=$(wc -c < "$semantic" | tr -d ' ')
  local sem_tokens=$((sem_size / CHARS_PER_TOKEN))
  echo "OK: Semantic memory distilled for '$squad_id' ($sem_size bytes, ~$sem_tokens tokens)"
}

cmd_compress() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh compress <squad-id> [--days N]"

  local dir="$MEMORY_ROOT/$squad_id"
  local history="$dir/history.md"
  [ -f "$history" ] || die "No history found for squad '$squad_id'"

  local days=7
  shift 2 || true
  while [ $# -gt 0 ]; do
    case "$1" in --days) days="$2"; shift 2 ;; *) shift ;; esac
  done

  # Archive full history
  cp "$history" "$dir/history-archive-$(date +%Y%m%d).md"

  # Keep only last N days of full sessions
  local cutoff_date
  cutoff_date=$(date -v-${days}d +"%Y-%m-%d" 2>/dev/null || date -d "$days days ago" +"%Y-%m-%d" 2>/dev/null || echo "2026-01-01")

  # Split into sessions, keep recent ones in full, compress old ones
  local temp_file="$dir/history-compressed.md"
  local in_old_session=0
  local current_session=""
  local session_date=""
  local compressed=""
  local recent=""

  while IFS= read -r line; do
    if [ "$line" = "---" ]; then
      if [ -n "$current_session" ]; then
        # Check if session is old
        session_date=$(echo "$current_session" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | head -1 || echo "")
        if [ -n "$session_date" ] && [[ "$session_date" < "$cutoff_date" ]]; then
          # Compress: keep only task + outcome line
          local task_line; task_line=$(echo "$current_session" | grep "^Task:" | head -1 || echo "")
          local outcome_line; outcome_line=$(echo "$current_session" | grep "^Outcome:" | head -1 || echo "")
          compressed="${compressed}---"$'\n'"$task_line | $outcome_line"$'\n'
        else
          recent="${recent}---"$'\n'"${current_session}"$'\n'
        fi
      fi
      current_session=""
    else
      current_session="${current_session}${line}"$'\n'
    fi
  done < "$history"

  # Handle last session
  if [ -n "$current_session" ]; then
    recent="${recent}---"$'\n'"${current_session}"
  fi

  # Write compressed history
  {
    if [ -n "$compressed" ]; then
      echo "## Compressed Sessions (before $cutoff_date)"
      echo "$compressed"
      echo ""
    fi
    echo "$recent"
  } > "$temp_file"

  mv "$temp_file" "$history"

  local old_size; old_size=$(wc -c < "$dir/history-archive-$(date +%Y%m%d).md" | tr -d ' ')
  local new_size; new_size=$(wc -c < "$history" | tr -d ' ')
  echo "OK: Compressed '$squad_id' — ${old_size} → ${new_size} bytes ($(( (old_size - new_size) * 100 / old_size ))% reduction)"
  echo "Archive saved to: history-archive-$(date +%Y%m%d).md"
}

cmd_list() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh list <squad-id>"
  local dir="$MEMORY_ROOT/$squad_id"
  [ -d "$dir" ] || { echo "No memory directory for squad '$squad_id'"; exit 0; }

  echo "Squad: $squad_id"
  echo "Directory: $dir"
  echo ""

  [ -f "$dir/meta.json" ] && { echo "Meta:"; cat "$dir/meta.json"; echo ""; }

  if [ -f "$dir/history.md" ]; then
    local size; size=$(wc -c < "$dir/history.md" | tr -d ' ')
    local sessions; sessions=$(grep -c "^---" "$dir/history.md" 2>/dev/null || echo 0)
    echo "Episodic: ${size} bytes, ~${sessions} sessions"
  fi

  if [ -f "$dir/semantic.md" ]; then
    local sem_size; sem_size=$(wc -c < "$dir/semantic.md" | tr -d ' ')
    echo "Semantic: ${sem_size} bytes"
  else
    echo "Semantic: not yet distilled (run: squad-memory.sh distill $squad_id)"
  fi
}

cmd_stats() {
  echo "=== Squad Memory Stats ==="
  echo "Root: $MEMORY_ROOT"
  echo ""
  [ -d "$MEMORY_ROOT" ] || { echo "No squads found."; exit 0; }

  for squad_dir in "$MEMORY_ROOT"/*/; do
    [ -d "$squad_dir" ] || continue
    local name; name=$(basename "$squad_dir")
    local epi_size="0" sem_size="0" sessions="0"
    [ -f "$squad_dir/history.md" ] && { epi_size=$(wc -c < "$squad_dir/history.md" | tr -d ' '); sessions=$(grep -c "^---" "$squad_dir/history.md" 2>/dev/null || echo 0); }
    [ -f "$squad_dir/semantic.md" ] && sem_size=$(wc -c < "$squad_dir/semantic.md" | tr -d ' ')
    echo "  $name: ~${sessions} sessions | episodic: ${epi_size}B | semantic: ${sem_size}B"
  done
}

cmd_flush() {
  [ -z "$squad_id" ] && die "Usage: squad-memory.sh flush <squad-id> [--keep-semantic]"
  local dir="$MEMORY_ROOT/$squad_id"
  [ -d "$dir" ] || die "No memory found for squad '$squad_id'"

  local keep_semantic=0
  shift 2 || true
  while [ $# -gt 0 ]; do
    case "$1" in --keep-semantic) keep_semantic=1; shift ;; *) shift ;; esac
  done

  # Archive everything first
  local archive="$dir/flush-archive-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$archive"
  cp "$dir"/*.md "$archive/" 2>/dev/null || true
  cp "$dir"/*.json "$archive/" 2>/dev/null || true

  # Flush
  rm -f "$dir/history.md"
  [ $keep_semantic -eq 0 ] && rm -f "$dir/semantic.md"

  # Reset meta
  local sem_exists="false"
  [ -f "$dir/semantic.md" ] && sem_exists="true"
  cat > "$dir/meta.json" << METAEOF
{
  "squadId": "$squad_id",
  "sessionCount": 0,
  "lastUpdated": "$(timestamp)",
  "hasSemanticMemory": $sem_exists,
  "lastFlushed": "$(timestamp)",
  "historyFile": "history.md"
}
METAEOF

  if [ $keep_semantic -eq 1 ]; then
    echo "OK: Flushed episodic memory for '$squad_id' (semantic preserved)"
  else
    echo "OK: Full flush for '$squad_id' — starting from scratch"
  fi
  echo "Archive: $archive/"
}

# --- Main ---
case "$cmd" in
  write)    cmd_write "$@" ;;
  read)     cmd_read "$@" ;;
  list)     cmd_list "$@" ;;
  stats)    cmd_stats "$@" ;;
  distill)  cmd_distill "$@" ;;
  compress) cmd_compress "$@" ;;
  flush)    cmd_flush "$@" ;;
  help|*)
    echo "Squad Memory System — Phase 2"
    echo ""
    echo "Commands:"
    echo "  write    <squad-id> <file|->          Write session memory"
    echo "  read     <squad-id> [options]          Read memory (semantic + episodic)"
    echo "  list     <squad-id>                    Show squad memory status"
    echo "  stats                                  Overview of all squads"
    echo "  distill  <squad-id>                    Extract semantic from episodic"
    echo "  compress <squad-id> [--days N]         Compress old sessions"
    echo ""
    echo "Read options:"
    echo "  --role ROLE       Filter by agent role"
    echo "  --limit N         Number of recent sessions (default: 3)"
    echo "  --tokens N        Token budget (default: 500)"
    echo "  --task \"desc\"     Task-aware relevance selection"
    ;;
esac
