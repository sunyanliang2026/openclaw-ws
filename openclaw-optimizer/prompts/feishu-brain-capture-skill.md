# Feishu Brain Capture Skill

Use this for normal Feishu Q&A turns after you already decided how to reply.

## Goal

Capture only durable signal into `gbrain`:

- decisions
- new facts
- standing preferences or rules
- follow-up items worth retrieving later

Do not store full transcripts. Do not store casual banter. Do not store `/newtask`.

## Steps

1. Reply to the Feishu message normally.
2. Decide whether the turn has durable signal.
3. If yes, run:

```bash
/home/ubuntu/.openclaw/workspace/openclaw-optimizer/scripts/capture-feishu-turn-to-brain.sh \
  --message '<raw_message>' \
  --reply '<reply_text>' \
  --summary '<1-3 sentence durable summary>' \
  --chat-id '<oc_xxx>' \
  --project internal-openclaw \
  --durable-type decision
```

4. If the script prints `skipped: ...`, do nothing else.

## Durable signal checklist

Capture when the turn contains one of these:

- a user decision or instruction that should affect future work
- a preference that will matter later
- a project fact or constraint worth reusing
- a follow-up action that may need retrieval

Skip when it is:

- `/newtask`
- heartbeat traffic
- greetings or acknowledgements
- casual banter
- ephemeral one-off info that is not worth retrieving later
