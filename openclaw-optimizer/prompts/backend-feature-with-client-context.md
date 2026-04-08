You are implementing a backend feature in an existing production codebase.

## Business context
- Client: {{client_name}}
- Goal: {{goal}}
- Non-goals: {{non_goals}}
- Existing behavior to preserve: {{existing_behavior}}

## Technical context
- Repo path: {{repo_path}}
- Branch: {{branch}}
- Relevant files:
  - {{file_1}}
  - {{file_2}}
- Constraints:
  - Keep backward compatibility for existing APIs.
  - Follow existing style and architecture.
  - Add/adjust tests for all changed behavior.

## Execution requirements
1. Read existing implementation before editing.
2. Make minimal, coherent changes.
3. Run lint/tests for impacted modules.
4. Summarize changed files and verification results.

## Failure-aware instructions
If prior attempt failed, apply these adjustments first:
- Failure reason: {{failure_reason}}
- Required correction: {{required_correction}}

## Done criteria
- Feature behaves as requested.
- No regression in existing path.
- Tests and lint pass.
- PR summary clearly explains tradeoffs and risks.
