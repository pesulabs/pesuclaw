---
name: memory-consolidator
description: Reviews the durable long-term memory (Mem0) to merge duplicate facts, resolve contradictions, and clean up the user's memory profile.
---

# Memory Consolidator Skill

This is an administrative maintenance skill. When invoked (typically via a scheduled Cron job), you must review the existing memories in the durable Mem0 system and consolidate them to keep the knowledge base clean and efficient.

## Phase 1: Review existing memories

First, use your `exec` or `bash` tool to retrieve the current memories for the specific user from the Orchestrator's Mem0 API. Replace `[USER_ID_OR_PHONE]` with the target user identifier.

```bash
curl -X GET "http://vm-orchestrator:8000/v1/memories/?user_id=[USER_ID_OR_PHONE]" \
     -H "Authorization: Bearer $MEM0_API_KEY"
```

Analyze the returned JSON list of memories. You are looking for:
1. **Duplicates:** Multiple memory records that mean the exact same thing.
2. **Contradictions:** Facts that conflict (e.g., "User is single" vs "User is married"). Use timestamps or recent context to determine the most up-to-date fact.
3. **Bloat:** Overly verbose facts that could be rewritten more concisely.

## Phase 2: Clean up and Synthesize

If you find duplicates, contradictions, or bloat, you must consolidate them. 

### Step 2a: Delete the old/redundant memories
For each redundant or outdated memory you want to replace, note its `id` from the GET request and delete it:

```bash
curl -X DELETE "http://vm-orchestrator:8000/v1/memories/[MEMORY_ID]/" \
     -H "Authorization: Bearer $MEM0_API_KEY"
```

### Step 2b: Add the newly synthesized memory (if applicable)
If you resolved a contradiction or combined duplicates, save the new, clean fact:

```bash
curl -X POST "http://vm-orchestrator:8000/v1/memories/" \
     -H "Authorization: Bearer $MEM0_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
           "messages": [{"role": "user", "content": "[NEW_CONSOLIDATED_FACT]"}],
           "user_id": "[USER_ID_OR_PHONE]",
           "agent_id": "'"$OPENCLAW_AGENT_ID"'"
         }'
```

*Note: You may execute multiple `curl` commands in a single `exec` tool call to speed up the process.*
