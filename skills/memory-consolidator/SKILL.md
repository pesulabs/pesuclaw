---
name: memory-consolidator
description: Reviews long-term memory to merge duplicates, resolve contradictions, and clean up the user's memory profile. Typically runs via scheduled Cron.
---

# Memory Consolidator Skill

This is an administrative maintenance skill. When invoked (typically via a scheduled Cron job), you must review the existing memories and consolidate them to keep the knowledge base clean and efficient.

## Phase 1: Review existing memories

Use `memory_list` to retrieve all current memories for the user:

```
memory_list()
```

Analyze the returned list. Look for:

1. **Duplicates:** Multiple memories that mean the exact same thing.
2. **Contradictions:** Facts that conflict (e.g., "User is single" vs "User is married"). Use the most recent one.
3. **Bloat:** Overly verbose memories that could be rewritten more concisely.
4. **Stale facts:** Information that is clearly outdated.

## Phase 2: Clean up and synthesize

### Step 2a: Delete redundant or outdated memories

For each memory you want to remove, use `memory_forget` with the memory's ID:

```
memory_forget("memory-id-here")
```

### Step 2b: Add newly synthesized memories (if applicable)

If you resolved a contradiction or combined duplicates, save the new clean fact:

```
memory_store("The user is married (updated from earlier record)")
```

## Guidelines

- Be conservative — only delete memories you are confident are duplicates or contradictions.
- When resolving contradictions, prefer the more recent information.
- After consolidation, summarize what you did (e.g., "Merged 3 duplicate entries about dietary preferences, removed 1 outdated address").
- Run consolidation for each user separately if multiple users exist.
