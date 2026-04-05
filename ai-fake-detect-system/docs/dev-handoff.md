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
- backend runtime was re-verified using repo venv:
  - `backend/.venv/bin/python backend/app.py`
  - `GET /health` returned success
  - `POST /detect/text` returned valid structured data
  - `POST /detect/image` returned valid structured data
- after validation, services were stopped again and ports `3000` / `5001` were confirmed clear

### Frontend
Frontend has moved from planning into real implementation.
ShipAny frontend structure has already been migrated into `frontend/`.

Current frontend direction:
- keep ShipAny shell/layout/theme/ui primitives
- replace business content with competition-specific pages
- use landing + detect + result workflow
- keep case showcase inside the landing page

Current reality check:
- demo routes now live in `frontend/src/app/[locale]/(demo)/`
- `http://127.0.0.1:3000/`, `/detect`, and `/result` have been re-validated and return `200`
- page content renders correctly for landing, detect, and result states
- the old "frontend routes hang under the ShipAny shell" blocker is no longer the current problem
- current follow-up work is normal product polish:
  - verify text submit UX in-browser
  - verify image submit UX in-browser
  - clean up deployment-facing configuration and demo residue

---

## Key Files Already Changed

### Docs
- `docs/frontend-next-step.md`
- `docs/frontend-minimum-plan.md`
- `docs/backend-next-step.md`

### Frontend code
- `frontend/src/lib/api.ts`
- `frontend/src/app/[locale]/(demo)/page.tsx`
- `frontend/src/app/[locale]/(demo)/detect/page.tsx`
- `frontend/src/app/[locale]/(demo)/result/page.tsx`

### Current uncommitted frontend work
- `frontend/src/app/[locale]/(demo)/detect/page.tsx`
- `frontend/src/app/[locale]/(demo)/layout.tsx`
- `frontend/src/app/[locale]/(demo)/page.tsx`
- `frontend/src/app/[locale]/(demo)/result/page.tsx`
- `frontend/src/app/[locale]/(landing)/layout.tsx`
- `frontend/src/app/[locale]/app-providers.tsx`
- `frontend/src/app/layout.tsx`
- `frontend/src/app/[locale]/layout.tsx`
- `frontend/src/config/index.ts`
- `frontend/src/config/locale/messages/en/common.json`
- `frontend/src/config/locale/messages/zh/common.json`
- `frontend/src/core/i18n/request.ts`
- `frontend/src/core/theme/index.ts`
- `frontend/src/core/theme/provider.tsx`

Current branch status:
- branch: `main`
- relative remote status during latest check: `main...origin/main [ahead 4]`
- latest key commit: `a468403 feat: add AI Fake Detect System demo frontend and docs`

---

## What Has Already Been Implemented

### Landing page
File:
- `frontend/src/app/[locale]/(demo)/page.tsx`

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
- `frontend/src/app/[locale]/(demo)/detect/page.tsx`

Current behavior:
- text/image tabs
- text input
- image file input
- validation messages
- calls backend through `src/lib/api.ts`
- stores result in browser storage and redirects to `/result`
- redirects to `/result`

Current in-progress change:
- detect result persistence is being strengthened
- current WIP writes result to both `sessionStorage` and `localStorage`
- goal: avoid losing result state after navigation/reload while debugging route issues

### Result page
File:
- `frontend/src/app/[locale]/(demo)/result/page.tsx`

Current behavior:
- reads stored detection result and renders the analysis view
- renders:
  - risk level
  - score
  - long-form summary
  - suspicious points
  - detail metrics
  - return actions
- includes text/image summary mapping and detail field mapping

Current in-progress change:
- result page now attempts to read from both `sessionStorage` and `localStorage`
- goal: keep result page usable after refresh or route retry

### API layer
File:
- `frontend/src/lib/api.ts`
- `frontend/src/app/api/detect/text/route.ts`
- `frontend/src/app/api/detect/image/route.ts`

Current behavior:
- defines `DetectResult`
- `detectText(content)`
- `detectImage(file)`
- unified response handling
- browser-side detection requests now go to same-origin Next routes:
  - `/api/detect/text`
  - `/api/detect/image`
- those Next routes proxy to the Flask backend using `NEXT_PUBLIC_API_BASE_URL`
- practical result:
  - browser clients no longer need direct reachability to Flask
  - temporary/public frontend exposure is simpler because only the frontend needs to be exposed

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
- use plain `corepack pnpm dev` as the default local dev command
- `corepack pnpm dev:turbo` is now the opt-in Turbopack path for higher-end machines only

### Verified commands
Successful:
- `corepack pnpm install`
- `corepack pnpm dev`
- `backend/.venv/bin/python backend/app.py`
- `curl http://127.0.0.1:3000/api/detect/text`
- `curl http://127.0.0.1:3000/api/detect/image`

### Runtime / resource findings from 2026-04-05
- Earlier "machine became unresponsive" behavior is now believed to be a frontend dev-mode issue, not a backend Flask issue.
- Primary risk factors now confirmed:
  - with Next.js `16.0.7`, plain `next dev` still starts in `Turbopack` mode by default in this repo environment
  - this means changing the package script from `next dev --turbopack` to `next dev` did **not** actually disable Turbopack
  - under route probing this can stall on `Compiling /[locale] ...` and encourage repeated retries / overlapping node processes
- Optimization already applied:
  - demo pages (`/`, `/detect`, `/result`) were moved into a separate `(demo)` route group so they no longer inherit the template landing provider stack
  - locale-level providers were split out of `src/app/[locale]/layout.tsx`
  - `ThemeProvider` + `AppContextProvider` + `Toaster` now live in a reusable `app-providers.tsx` wrapper and are only attached to route groups that actually need them
  - several layouts stopped importing `LocaleDetector` when locale detection is disabled by default, reducing unnecessary client-side compile work in landing/chat/admin route groups
  - `src/core/i18n/request.ts` now loads message namespaces by pathname instead of importing every locale JSON file on every request
  - `src/core/theme/index.ts` no longer uses dynamic string imports for theme pages/layouts/blocks; it now uses an explicit registry for the only existing theme (`default`)
- Controlled validation in dev mode:
  - `corepack pnpm dev` starts `Next.js 16.0.7 (Turbopack)` in this environment
  - a single cold `GET /` completed with `200`, but took about `18.0s` total with `compile: 16.9s`
  - a controlled `GET /detect` completed with `200` in about `2.7s` after the server was already warm
  - process snapshots showed `next-server` growing from about `750MB RSS` idle to roughly `1.4GB` to `1.65GB RSS` during route compilation
- Controlled validation after provider/i18n scoping:
  - cold `GET /` improved to about `8.3s` total with `compile: 7.5s`
  - cold-ish `GET /detect` completed in about `2.5s` with `compile: 2.3s`
  - `next-server` RSS during this run was about `1.25GB` on `/` and about `1.30GB` after `/detect`
- Additional controlled validation after theme registry change:
  - after restarting dev server, `GET /` completed in about `3.2s` total with `compile: 2.5s`
  - process snapshot during that run showed `next-server` around `580MB RSS`
  - caveat: this run still had Turbopack filesystem cache enabled, so treat it as "optimized current behavior" rather than a perfectly isolated apples-to-apples baseline
- Webpack comparison:
  - explicit `npx next dev --webpack` was verified
  - it does avoid the hidden "plain dev still means Turbopack" ambiguity
  - however, cold `GET /` was still heavy in this repo: about `21.0s` total with `compile: 20.0s`
  - webpack mode therefore is not a silver bullet for this project's resource issue
- Current interpretation:
  - the real problem is expensive first compile of the locale app shell in dev mode, not the Flask backend
  - the machine-freeze failure mode likely comes from combining that expensive compile with repeated probes, browser automation, or stacked `pnpm dev` processes
  - the highest-value optimizations so far were:
    - scoping global client providers away from the demo routes
    - stopping all-at-once locale message loading for every request
    - replacing dynamic theme import contexts with an explicit default-theme registry
  - next investigation should focus on any remaining heavy imports that still sit behind the locale shell or template landing pages outside the demo subtree
- Practical safety rule:
  - never assume `next dev` means webpack in Next 16; check the startup banner
  - keep validation to one frontend dev process at a time
  - probe routes sequentially, not concurrently
  - avoid browser automation during cold compile unless necessary
  - if resource pressure reappears, stop the dev server before retrying

### Browser tool note
During one validation round, browser automation was unavailable due to browser tool timeout.
Do not depend on browser tool availability.
Alternative validation methods already used:
- dev server logs
- HTTP probing

---

## Current Open Problem
There is no longer a route-availability blocker on the demo pages.

Current focus:
- confirm browser-side text submission reaches `/result` and persists across reload
- confirm browser-side image submission reaches `/result`
- keep simplifying any deployment-hostile assumptions, but the direct browser-to-Flask coupling has now been removed
- clean up demo/test residue like uploaded sample files if they are not needed

More concrete framing:
- backend APIs are working
- demo frontend routes are working
- remaining work is around UX verification, configuration hygiene, and cleanup
- deployment direction is now documented as a single public frontend entry with internal frontend-to-backend proxying
- current suspicion is outer layout/theme/i18n shell interaction
- current WIP changes are simplifying root/landing theme wrapping to isolate the render blockage
- do not assume locale redirect behavior is the root cause before checking layout/request pipeline

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
   - inspect current edits in:
     - `frontend/src/app/layout.tsx`
     - `frontend/src/app/[locale]/(landing)/layout.tsx`
     - `frontend/src/core/theme/provider.tsx`
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
- there are active uncommitted frontend edits trying to simplify layout/theme wrapping and harden result persistence
