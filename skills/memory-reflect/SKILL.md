---
name: memory-reflect
description: A meta-skill for self-review. The agent reviews its recent performance and knowledge gaps, and stores useful self-reflections in long-term memory.
---

# Memory Reflect Skill

As an AI agent, you should periodically reflect on your own performance, communication style, and interactions to improve over time. This skill is typically invoked via a scheduled Cron job.

## How to use

Reflect on recent sessions or interactions. Identify:

1. **Knowledge Gaps:** What did you not know that you should learn or look up for next time?
2. **Communication Adjustments:** Did the user correct you? Did they ask you to be more concise, use a different format, or change your tone?
3. **Important Patterns:** Are there behavioral patterns or recurring requests from the user?

Once you have formulated a clear, concise reflection, save it using `memory_store`:

```
memory_store("Always verify the project name before suggesting code modifications")
```

### Important rules

- Write reflections as direct instructions or behavioral notes, e.g., "Always verify the project name before suggesting code modifications", NOT "I learned that I should verify the project name."
- Before storing, use `memory_search` to check if a similar reflection already exists. Update rather than duplicate.
- Keep reflections actionable and specific — avoid vague observations.
- Use `memory_list` to review existing reflections and ensure consistency.
