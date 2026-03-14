---
name: memory-hygiene
description: Periodic maintenance skill that audits memory quality, removes stale entries, and enforces retention policies. Typically runs via scheduled Cron.
---

# Memory Hygiene Skill

This is a scheduled maintenance skill that ensures the long-term memory store remains clean, relevant, and within size limits. Typically invoked via Cron (e.g., weekly).

## What to audit

Use `memory_list` to retrieve all stored memories, then evaluate each one:

### 1. Staleness check
- Remove memories that reference time-sensitive information that is now outdated (e.g., "User has a meeting next Tuesday" from weeks ago).
- Remove memories about completed one-time events.

### 2. Relevance check
- Remove memories that are too vague to be useful (e.g., "User mentioned something about food").
- Remove memories that duplicate information already in the agent's knowledge base or workspace files.

### 3. Privacy check
- Flag and remove any memories that contain sensitive data that shouldn't be persisted:
  - Credit card numbers or payment details
  - Passwords or authentication tokens
  - Full addresses or government IDs
- If sensitive data is found, delete immediately with `memory_forget` and note it in your summary.

### 4. Size check
- If the total memory count exceeds 200 entries per user, prioritize consolidation.
- Use `memory-consolidator` patterns to merge related memories.

## How to execute

```
# 1. Get all memories
memory_list()

# 2. For each stale/irrelevant/sensitive memory:
memory_forget("memory-id")

# 3. Summarize actions taken
```

## Output

After completing hygiene, produce a brief summary:
- Memories reviewed: N
- Memories removed: N (with reasons)
- Sensitive data found: yes/no
- Recommendations: any follow-up actions needed
