# Dev Handoff

## Purpose
This file is for resume-after-context-loss handoff.
If a future session needs to continue this project, read this file first, then read:
- `docs/frontend-next-step.md`
- `docs/frontend-minimum-plan.md`
- `docs/backend-next-step.md`

---

## Project Identity
- Project name: `AI Fake Detect System`
- Project directory: `/home/ubuntu/.openclaw/workspace/ai-fake-detect-system`
- Reference template: `/home/ubuntu/.openclaw/workspace/shipany-template`
- Rule: do **not** modify `shipany-template` directly; actual work happens in `ai-fake-detect-system/`

---

## Current Overall Status

### Backend
Backend minimum closed loop is complete.
Already verified:
- `/health`
- `/detect/text`
- `/detect/image`

Backend stack:
- Flask
- rule-based v1 text/image detectors

Important backend note:
- image endpoint has already been tested with a real uploaded image and returns success

### Frontend
Frontend has moved from planning into real implementation.
ShipAny frontend structure has already been migrated into `frontend/`.

Current frontend direction:
- keep ShipAny shell/layout/theme/ui primitives
- replace business content with competition-specific pages
- use landing + detect + result workflow
- keep case showcase inside the landing page

---

## Key Files Already Changed

### Docs
- `docs/frontend-next-step.md`
- `docs/frontend-minimum-plan.md`
- `docs/backend-next-step.md`

### Frontend code
- `frontend/src/lib/api.ts`
- `frontend/src/app/[locale]/(landing)/page.tsx`
- `frontend/src/app/[locale]/(landing)/detect/page.tsx`
- `frontend/src/app/[locale]/(landing)/result/page.tsx`

---

## What Has Already Been Implemented

### Landing page
File:
- `frontend/src/app/[locale]/(landing)/page.tsx`

Current behavior:
- no longer uses original dynamic landing homepage content path
- now shows project-specific landing content
- includes:
  - hero section
  - capability cards
  - text/image case showcase sections
  - usage/disclaimer section
  - CTA buttons

### Detect page
File:
- `frontend/src/app/[locale]/(landing)/detect/page.tsx`

Current behavior:
- text/image tabs
- text input
- image file input
- validation messages
- calls backend through `src/lib/api.ts`
- stores result in `sessionStorage`
- redirects to `/result`

### Result page
File:
- `frontend/src/app/[locale]/(landing)/result/page.tsx`

Current behavior:
- reads `detect-result` from `sessionStorage`
- renders:
  - risk level
  - score
  - long-form summary
  - suspicious points
  - detail metrics
  - return actions
- includes text/image summary mapping and detail field mapping

### API layer
File:
- `frontend/src/lib/api.ts`

Current behavior:
- defines `DetectResult`
- `detectText(content)`
- `detectImage(file)`
- unified response handling

---

## Important Route / Framework Findings

### ShipAny shell behavior
This template is not a simple static frontend.
It uses:
- Next.js app router
- `next-intl`
- `[locale]` route grouping
- landing/auth/admin/docs/chat route groups
- theme/layout shell

### Locale behavior
Important discovery:
- `localePrefix = 'as-needed'`
- default locale is effectively `en`
- `/en`, `/en/detect`, `/en/result` redirect to `/`, `/detect`, `/result`

Implication:
- when validating real user-facing routes, prioritize:
  - `/`
  - `/detect`
  - `/result`

This redirect behavior is currently considered template behavior, not necessarily a bug.

---

## Environment / Tooling Findings

### Package manager
- keep using `pnpm`
- do not switch this project to `npm` now
- use `corepack pnpm ...` if global `pnpm` command is unavailable

### Verified commands
Successful:
- `corepack pnpm install`
- `corepack pnpm dev`

### Browser tool note
During one validation round, browser automation was unavailable due to browser tool timeout.
Do not depend on browser tool availability.
Alternative validation methods already used:
- dev server logs
- HTTP probing

---

## Current Open Problem
Frontend minimum closed loop is still being validated end-to-end in the browser.

Current focus:
- verify that `/`, `/detect`, and `/result` render under the ShipAny layout shell
- confirm text submission reaches `/result`
- confirm image submission reaches `/result`
- make sure the UI is stable enough for a live check in the browser

This is the main current technical focus.

---

## Recommended Next Steps
Continue in this order:

1. start frontend dev server again if needed
   - `corepack pnpm dev`

2. validate actual routes:
   - `/`
   - `/detect`
   - `/result`

3. inspect dev logs during route load to identify any blocking render/layout issue

4. if route/render issue exists:
   - inspect outer landing/layout/theme dependencies first
   - do not immediately blame locale redirects

5. once rendering is stable:
   - test text submission from detect page
   - verify successful redirect to result page
   - test image submission from detect page
   - verify successful redirect to result page

6. after full render + submission validation:
   - fix any route path detail
   - lightly polish UI

---

## Resume Prompt Suggestion
If future context is lost, a good restart instruction is:

> Read `docs/dev-handoff.md`, `docs/frontend-next-step.md`, `docs/frontend-minimum-plan.md`, and `docs/backend-next-step.md`, then continue validating the frontend routes `/`, `/detect`, and `/result` and fix the current render/runtime issue.

---

## Short Resume Summary
If you only have 10 seconds:
- backend works
- ShipAny frontend has been migrated
- landing/detect/result pages have been created
- docs are updated
- current blocker is frontend route/render validation under ShipAny shell
