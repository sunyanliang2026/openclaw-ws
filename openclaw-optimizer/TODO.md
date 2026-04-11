# OpenClaw Deep-Use TODO

This file tracks the next practical upgrades for turning the current OpenClaw setup into a stable daily system instead of a collection of scripts.

## P0: Make It Reliable

- [ ] Standardize task lifecycle
  - Define one canonical flow: `create -> run -> review -> archive`.
  - Stop leaving finished or discarded work in `runtime/tasks/active`.
  - Make `ready_for_review` a transient state, not a parking lot.

- [ ] Add a real archive step
  - Add a script that moves completed or discarded tasks out of the active queue.
  - Record why a task was archived: merged, abandoned, duplicate, smoke-only, infra-only.
  - Keep a minimal searchable history after archival.

- [ ] Separate repo state from runtime state
  - Keep Git tracking only config, templates, prompts, docs, and reusable scripts.
  - Treat locks, task-runs, temporary task manifests, session artifacts, and logs as runtime-only.
  - Periodically verify `.gitignore` still matches actual runtime output paths.

- [ ] Formalize failure classification
  - Require every failed task to map to one of: `infra`, `auth`, `repo-state`, `code`, `ci`, `rate-limit`, `unknown`.
  - Store the classification on the task record.
  - Make retry behavior conditional on classification instead of generic retry.

- [ ] Add a single health check entrypoint
  - Create one command that checks auth, gateway, Feishu channel, active listeners, memory, swap, and git cleanliness.
  - Keep the output short enough to use during incidents.
  - Make it safe to run repeatedly.

## P1: Make It Efficient

- [ ] Define per-project defaults beyond skills
  - For each project, define default branch naming, worktree root, verification command, PR requirement, and cleanup policy.
  - Make smoke-only tasks opt out of unnecessary branch and PR flow.

- [ ] Tighten Feishu `/newtask` dispatch
  - Reject malformed payloads early.
  - Add duplicate detection for obviously repeated tasks.
  - Reply with task id, project, status, and worktree/session details when available.
  - Return failure reasons in a compact, operator-friendly format.

- [ ] Standardize long-running session hosting
  - Decide on one session model for task execution and dev servers.
  - If tmux is kept, codify session naming, attach rules, and cleanup behavior.
  - Eliminate ad hoc background processes where task ownership becomes unclear.

- [ ] Produce a task summary artifact
  - Each completed task should emit a compact summary file.
  - Include commands run, result, evidence, PR link, and next step.
  - Make this the first place to inspect before reading logs.

## P2: Add Targeted Capability

- [ ] Add a local healthcheck skill or equivalent workflow
  - Cover service status, ports, auth state, disk, memory, swap, and gateway reachability.
  - Optimize for machine triage, not generic cloud monitoring.

- [ ] Add a session-management skill or equivalent workflow
  - Support listing sessions, attaching, restarting failed sessions, and cleaning stale ones.
  - Reduce recurrence of session lifecycle failures.

- [ ] Improve GitHub workflow integration
  - Make PR state, review comments, mergeability, and CI summary available through one operator path.
  - Avoid jumping between local git inspection and GitHub manually for routine checks.

- [ ] Add project bootstrap templates
  - New projects should start with task schema, verification command, cleanup policy, and default orchestration rules already defined.

## Immediate Next Steps

- [ ] Implement archive/cleanup workflow first.
- [ ] Add a health check command second.
- [ ] Standardize tmux or session hosting third.
- [ ] Revisit Feishu and GitHub workflow enhancements after the runtime loop is stable.
