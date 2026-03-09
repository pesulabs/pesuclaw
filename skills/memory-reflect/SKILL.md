---
name: memory-reflect
description: A meta-skill for self-review. The agent reviews its recent performance and knowledge gaps, and stores useful self-reflections in durable memory (Mem0).
---

# Memory Reflect Skill

As an AI agent, you should periodically reflect on your own performance, communication style, and interactions to improve over time. This skill is typically invoked automatically via a scheduled Cron job.

## How to use

When you use this skill, reflect on the recent sessions or interactions you have had. Identify:
1. **Knowledge Gaps:** What did you not know that you should learn or look up for next time?
2. **Communication Adjustments:** Did the user correct you? Did they ask you to be more concise, use a different format, or change your tone?
3. **Important Patterns:** Are there behavioral patterns or recurring requests from the user?

Once you have formulated a clear, concise reflection, use your `exec` or `bash` tool to save it into the Orchestrator's Mem0 system as a permanent preference/instruction for yourself:

```bash
curl -X POST "http://vm-orchestrator:8000/v1/memories/" \
     -H "Authorization: Bearer $MEM0_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{
           "messages": [{"role": "user", "content": "[REFLECTION]"}],
           "user_id": "[USER_ID_OR_PHONE]",
           "agent_id": "'"$OPENCLAW_AGENT_ID"'"
         }'
```

### Important Usage Rules:
- Replace `[REFLECTION]` with a direct instruction or fact about your own behavior, e.g., "Always verify the project name before suggesting code modifications.", NOT "I learned that I should verify the project name."
- Replace `[USER_ID_OR_PHONE]` with the identifier of the specific user these reflections apply to. Use `"default"` if it applies to your general persona rather than a specific user.
