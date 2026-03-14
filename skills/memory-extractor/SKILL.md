---
name: memory-extractor
description: Extracts durable facts, user preferences, and entity knowledge from the current conversation and saves them to long-term memory via the embedded mem0 plugin.
---

# Memory Extractor Skill

You have a built-in long-term memory system powered by the mem0 plugin. When a user tells you a fact, preference, or important detail that you should remember for future conversations, you MUST extract and save it.

## When to extract

- **DO** extract durable facts (e.g., "User is a vegetarian", "User's wife is named Sarah").
- **DO** extract user preferences (e.g., "User prefers concise answers", "User likes dark mode").
- **DO** extract important decisions or choices the user has made.
- **DO NOT** extract transient information (e.g., "User is asking about pricing today").
- **DO NOT** extract facts about yourself or your system capabilities.
- **DO NOT** extract sensitive data the user hasn't consented to store (passwords, payment details).

## How to use

Use the `memory_store` tool to save extracted facts:

```
memory_store("The user is a vegetarian and prefers plant-based recipes")
```

### Important rules

1. Write facts in clear, concise third-person language from the user's perspective (e.g., "The user has 3 dogs", NOT "I learned that you have 3 dogs").
2. One fact per `memory_store` call — don't combine unrelated facts.
3. Before storing, use `memory_search` to check if a similar memory already exists. If it does, update it rather than creating a duplicate.
4. The mem0 plugin automatically handles user and agent scoping — you don't need to specify user_id or agent_id.

## Available memory tools

- `memory_store` — save a new memory
- `memory_search` — find relevant past memories (use before storing to avoid duplicates)
- `memory_list` — see all stored memories for current user
- `memory_get` — retrieve a specific memory by ID
- `memory_forget` — remove a specific memory by ID
