# Frontend Next Step

## Goal
Build the first demo-ready frontend version for **AI Fake Detect System**.

This version should be:
- runnable
- connected to backend APIs
- visually complete enough for competition demo
- based on the ShipAny-style frontend direction

---

## Current Progress Sync
Completed so far:
- migrated ShipAny frontend project structure into `frontend/`
- kept ShipAny layout/theme/i18n shell and replaced the landing homepage entry
- confirmed reusable UI primitives already exist in the template (`Button`, `Card`, `Badge`, `Tabs`, `Input`, `Textarea`)
- created `src/lib/api.ts`
- created landing detection page entry at `src/app/[locale]/(landing)/detect/page.tsx`
- created result page at `src/app/[locale]/(landing)/result/page.tsx`
- updated planning from three pages to a **two-page structure**:
  - landing page with case showcase sections
  - result page
- installed frontend dependencies successfully using `corepack pnpm install`
- started Next.js dev server successfully using `corepack pnpm dev`

Important findings:
- current ShipAny locale behavior uses `localePrefix = 'as-needed'`
- with default locale `en`, `/en`, `/en/detect`, and `/en/result` redirect to `/`, `/detect`, and `/result`
- current verification focus should therefore prioritize the real accessible routes:
  - `/`
  - `/detect`
  - `/result`
- browser tool was temporarily unavailable during validation, so verification shifted to dev-server logs and HTTP probing

Open verification items:
- confirm that `/`, `/detect`, and `/result` render successfully without blocking on outer landing/theme dependencies
- verify the detection page can submit real text requests and reach the result page successfully
- verify the detection page can submit real image requests and reach the result page successfully
- adjust route links if locale-aware routing or landing-group routing needs correction after first full render test

---

## Scope of Version 1
Version 1 focuses on a **two-page structure** for the minimum usable frontend closed loop.

Included pages:
1. Home / Landing Detection page
2. Result page

The landing page should contain:
- project introduction
- detection entry
- capability blocks
- case showcase sections
- version disclaimer

Not included in version 1:
- login / register
- payment / subscription
- dashboard / admin system
- export / share
- history storage
- database integration
- complex animation
- advanced responsive optimization
- standalone cases page as a required deliverable

---

## Page Structure

### 1. Home / Landing Detection Page
Path target:
- `src/app/[locale]/(landing)/page.tsx`

Main responsibilities:
- show project title and intro
- act as the main landing page in ShipAny style
- present capability explanation blocks
- present case showcase sections directly on the same page
- provide entry into the dedicated detection workflow
- show version disclaimer

Core blocks:
- hero / page header
- primary CTA to detection page
- capability cards
- text case showcase section
- image case showcase section
- usage / disclaimer section

### Detection workflow page
Implemented separately at:
- `src/app/[locale]/(landing)/detect/page.tsx`

Responsibilities:
- switch between text detection and image detection
- accept text input
- accept image upload
- submit detection request
- validate inputs
- store result to `sessionStorage`
- redirect to result page

---

### 2. Result Page
Path target:
- `src/app/[locale]/(landing)/result/page.tsx`

Main responsibilities:
- read detection result from `sessionStorage`
- show risk level, score, suspicious points, and details
- show long-form summary text based on detection type and risk level
- provide return path to detection and home page
- keep the page focused on explanation and result rendering

Core blocks:
- page header
- risk badge
- score card
- long-form summary text
- suspicious points list
- detail panel
- action buttons
- result disclaimer

---

## Navigation Flow
Recommended minimum routing in product intent:
- `/` -> Home / Landing Detection page
- `/detect` -> Detection workflow page
- `/result` -> Result page

Recommended page relationships:
- Home -> Detect
- Detect -> Result (after successful detection)
- Result -> Detect
- Result -> Home

Case showcase is embedded inside the landing page in version 1, so no standalone `/cases` page is required for the minimum demo.

---

## API Integration Plan

### Backend base
Current backend target:
- `http://127.0.0.1:5001`

### Text detection
- `POST /detect/text`
- request body:
```json
{
  "content": "text here"
}
```

### Image detection
- `POST /detect/image`
- request body: `multipart/form-data`
- field name: `file`

### Frontend API file
Path:
- `src/lib/api.ts`

Should include:
- `DetectResult` type
- `detectText(content)`
- `detectImage(file)`
- unified response handling
- unified error handling

---

## Result Rendering Rules

### Risk level mapping
- `low` -> 低风险
- `medium` -> 中风险
- `high` -> 高风险

### Color mapping
- `low` -> green
- `medium` -> orange
- `high` -> red

### Long-form summary strategy
Use long-form summary text by default.

#### Text summaries
- `text.low`: 系统未发现明显高风险伪造特征，但建议继续结合发布来源与上下文进行判断。
- `text.medium`: 系统检测到部分可疑语言特征，文本可能存在模板化或重复性表达，建议进一步人工复核。
- `text.high`: 系统检测到较多可疑语言特征，文本可能存在较明显的模板化、重复化或来源不明问题，建议重点核查。

#### Image summaries
- `image.low`: 系统未发现明显高风险图像特征，但建议继续结合图片来源、拍摄背景与使用场景进行判断。
- `image.medium`: 系统检测到部分异常图像特征，图片可能存在元数据异常或局部处理痕迹，建议进一步核查。
- `image.high`: 系统检测到较多异常图像特征，图片可能存在明显处理痕迹或生成式特征，建议重点核查来源与细节。

### Detail field mapping

#### Text details
- `length` -> 文本长度
- `sentence_count` -> 句子数量
- `repeat_ratio` -> 重复率
- `avg_sentence_length` -> 平均句长
- `template_hits` -> 模板命中数
- `has_source_hint` -> 来源提示

#### Image details
- `width` -> 图片宽度
- `height` -> 图片高度
- `has_exif` -> EXIF 信息
- `blur_score` -> 模糊度
- `smoothness_score` -> 平滑度

### Formatting rules
- boolean -> 是 / 否
- decimal -> keep 2 digits
- `repeat_ratio` -> percentage display
- null / undefined -> 暂无
- empty array -> 无

---

## Development Priority

### Phase 1
1. make `frontend/` runnable
2. replace the current landing home entry with competition landing content
3. create `src/lib/api.ts`
4. create dedicated detection workflow page

### Phase 2
5. build result page basic structure
6. add summary mapping / risk mapping / detail mapping

### Phase 3
7. connect text detection flow
8. connect image detection flow

### Phase 4
9. embed text case showcase and image case showcase into the landing page
10. unify navigation across home, detect, and result

### Phase 5
11. unify layout, spacing, buttons, cards, and colors
12. polish text and UI lightly for demo

---

## Acceptance Criteria

### Home page done when:
- page opens normally inside current ShipAny landing structure
- capability blocks exist
- case showcase sections exist on the same page
- detection CTA exists

### Detect page done when:
- detect page opens normally
- text / image switch works
- text input exists
- image upload exists
- submit button exists
- validation message works

### Result page done when:
- result page opens normally
- no-result fallback exists
- risk level, score, points, and details are visible
- long-form summary text is visible

### Text integration done when:
- text can be submitted from detect page
- real backend response appears on result page

### Image integration done when:
- image can be uploaded from detect page
- real backend response appears on result page

### Version 1 done when:
- home, detect, and result routes are navigable
- text detection works
- image detection works
- result page is explainable
- landing page includes case showcase
- page style is consistent enough for demo

---

## Current Immediate Next Tasks
1. finish validating `/`, `/detect`, and `/result` real render behavior
2. fix any route or layout issue caused by current ShipAny outer shell
3. finish text integration first
4. finish image integration second
5. polish navigation between landing, detect, and result

---

## Note
Version 1 is meant for a competition demo, not for production completeness.
Keep the implementation small, clear, and explainable.
