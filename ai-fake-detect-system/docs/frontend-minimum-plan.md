# Frontend Minimum Plan

## Goal
Build a minimum visible frontend for AI Fake Detect System.

## Stage target
Create a simple web UI that can:
1. introduce the project clearly
2. guide users from landing page into detection workflow
3. choose detection type
4. upload image or input text
5. submit request to backend
6. display risk score, level, suspicious points, and detail metrics
7. showcase example cases on the landing page

## Current progress sync
Already completed:
- ShipAny frontend project has been migrated into `frontend/`
- landing homepage entry has been replaced with project-specific content
- `src/lib/api.ts` has been created
- dedicated detection page has been created at `src/app/[locale]/(landing)/detect/page.tsx`
- result page has been created at `src/app/[locale]/(landing)/result/page.tsx`
- frontend dependencies were installed successfully with `corepack pnpm install`
- Next.js dev server was started successfully with `corepack pnpm dev`

Current findings:
- template locale setting uses `localePrefix = 'as-needed'`
- default locale paths may redirect to non-prefixed routes
- verification focus is currently on actual accessible routes and route/layout behavior

## Minimum page structure

### 1. Landing Page
Core blocks:
- Project title
- Short project description
- Main CTA to detection page
- Capability explanation cards
- Text case showcase section
- Image case showcase section
- Disclaimer / usage notes

### 2. Detection Page
Core blocks:
- Detection type tabs:
  - Image Detection
  - Text Detection
- Image upload area
- Text input area
- Submit button
- Validation / error display
- Return to home action

### 3. Result Page
Core blocks:
- Detection type
- Risk level
- Risk score
- Long-form summary text
- Suspicious points list
- Detail metrics
- Back buttons

## Suggested component structure
- Header
- DetectionTypeSwitcher
- ImageUploadForm
- TextInputForm
- CapabilityCards
- CaseShowcaseSection
- ResultCard
- RiskBadge
- DetailPanel

## API connections

### Text API
POST `/detect/text`
Content-Type: application/json

Request:
```json
{
  "content": "text here"
}
```

### Image API
POST `/detect/image`
Content-Type: multipart/form-data

Request fields:
- file

## Expected result fields
- success
- type
- risk_level
- score
- points
- details
- message

## Frontend display mapping

### Risk level colors
- low -> green
- medium -> orange
- high -> red

### Score display
- 0-39: low risk
- 40-69: medium risk
- 70-100: high risk

### Summary strategy
Use long-form result summary text by default.

## First implementation order
1. Build the landing page first
2. Build the dedicated detection page
3. Make text submission work first
4. Render text result page
5. Make image upload work
6. Render image result page
7. Validate route behavior under current ShipAny layout/i18n shell
8. Polish layout only after both routes work

## Notes
- Do not over-design first
- Prioritize working submission + result rendering
- Keep the first version suitable for demo, not for perfection
- Version 1 uses landing + detect + result workflow under the ShipAny shell
- Case content belongs to the landing page in version 1
