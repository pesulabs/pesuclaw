---
name: memory-extractor
description: Extracts durable facts, user preferences, and entity knowledge from the current conversation and saves them to the long-term memory system (Mem0).
---

# Memory Extractor Skill

You have access to a centralized long-term memory system (Mem0) running on the platform's Orchestrator instance. When a user tells you a fact, preference, or important detail that you should remember for future conversations across multiple sessions, you MUST extract and save it to this system.

## When to use

- **DO** extract durable facts (e.g., "User is a vegetarian", "User's wife is named Sarah").
- **DO** extract user preferences (e.g., "User prefers concise answers", "User likes dark mode").
- **DO NOT** extract transient information (e.g., "User is asking about pricing today", "User needs help with a bug right now").
- **DO NOT** extract facts about yourself or your system capabilities.

## How to use

To save a new memory, you must use your `exec` or `bash` tool to execute the following `curl` command against the internal Mem0 API. 

```bash
curl -X POST "http://vm-orchestrator:8000/v1/memories/" \
     -H "Authorization: Bearer $MEM0_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
           "messages": [{"role": "user", "content": "[FACT]"}],
           "user_id": "[USER_ID_OR_PHONE]",
           "agent_id": "'"$OPENCLAW_AGENT_ID"'"
         }'
```

### Important Usage Rules:
1. **[FACT]**: Replace this with the specific fact you are extracting, written in clear, concise language from the perspective of the user (e.g., "The user has 3 dogs", NOT "I learned that you have 3 dogs").
2. **[USER_ID_OR_PHONE]**: Replace this with the unique identifier of the user you are currently talking to. This could be their phone number (if on WhatsApp), their Discord ID, or their name. If not easily identifiable, use `"default"`.
3. The variables `$MEM0_API_KEY` and `$OPENCLAW_AGENT_ID` will be automatically populated by the environment. Do not try to hardcode them.
