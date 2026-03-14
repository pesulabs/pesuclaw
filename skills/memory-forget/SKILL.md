---
name: memory-forget
description: Allows the user to request deletion of specific memories from long-term storage. Supports GDPR/privacy-compliant data removal.
---

# Memory Forget Skill

When a user asks you to forget something, delete specific memories, or requests data removal, use this skill to comply.

## When to use

- User explicitly says "forget that", "delete my data", "remove that memory"
- User corrects outdated information and wants the old version removed
- Privacy/GDPR requests for data deletion
- User asks to "start fresh" or "clear my history"

## How to use

### Step 1: Find the relevant memories

Use `memory_search` to find memories matching what the user wants forgotten:

```
memory_search("the topic the user wants forgotten")
```

Or use `memory_list` to show all memories:

```
memory_list()
```

### Step 2: Confirm with the user

Before deleting, show the user what you found and confirm they want it removed. Example:

> I found these memories related to your request:
> 1. "User prefers dark chocolate over milk chocolate"
> 2. "User's favorite dessert is tiramisu"
>
> Should I remove both, or just one?

### Step 3: Delete confirmed memories

Use `memory_forget` with the memory ID:

```
memory_forget("memory-id-here")
```

### Step 4: Confirm deletion

Tell the user what was removed: "Done — I've forgotten your chocolate preference."

## Guidelines

- Always confirm before deleting unless the user is very explicit.
- For "forget everything" requests, use `memory_list` to get all memories, then delete each one.
- Log what was deleted in your response so the user has a record.
- If no matching memories are found, inform the user: "I don't have any stored memories about that topic."
