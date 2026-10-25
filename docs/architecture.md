# Architecture

This document describes where TrainWise is going and why. [deployment.md](deployment.md) covers how the current system is deployed.

## Positioning

TrainWise is an **iOS-first strength-training log with an AI coach**. The product ships as **IronSage** (see [Name](#name)). The repository and AWS resources keep the `trainwise` name; users never see it.

- **Users** lift weights. They log exercises, sets, reps and load, for example a chest press on a specific machine at a specific weight.
- **Core loop**: log a session, then before the next one the coach suggests what to do (exercise, load, sets and reps) and explains why. The suggestion uses past sessions and Apple Health data (sleep, heart rate variability, resting heart rate, heart rate during earlier workouts).
- **Business model**: logging, history and charts are free. The AI coach is a subscription.
- **Platforms**: iPhone app (main product), including the foldable iPhone Duo. The web app shrinks to a landing page plus privacy and support pages. No Android, no iPad or Apple Watch app in version 1.
- **Languages**: English and Chinese.
- **Constraints**: one developer, costs close to zero until there are paying users.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Sign-in | Clerk (email code, Google, Apple) | Shared by web and iOS. The API only verifies tokens and stores no passwords |
| Backend runtime | FastAPI on AWS Lambda, Neon Postgres, AWS CDK | Pay per use. At 10,000 users × 20 requests a day the average load is 2–3 requests per second |
| API versioning | Everything under `/v1` | Installed app versions keep working when `/v2` ships |
| Health data | Apple HealthKit only | No Android, so no cross-platform aggregator (such as Terra) is needed |
| Next-session suggestion | Deterministic progression rules first, then Claude adjusts and explains | Numbers stay stable and testable. The model only sees a small summary, which keeps calls cheap |
| Subscriptions (v1) | StoreKit 2 only | See [Subscriptions](#subscriptions) |
| Nutrition | Version 2 | Large feature that is not part of the core strength loop |

## Name

**IronSage**: "iron" for lifting, "sage" for a coach that explains its advice.

Checked on 2026-10-24:

- App Store: no app named IronSage or Iron Sage in the US, UK, Canada, Australia, Singapore, Hong Kong, Taiwan, Japan or Germany stores. "TrainWise" was dropped because four App Store apps already use it.
- USPTO: no trademark for "ironsage" or "iron sage".
- Domains: `ironsage.app` is unregistered (preferred). `ironsage.com` belongs to an unrelated site; `getironsage.com` and `ironsageapp.com` are unregistered.

The name is only ours once the app is created in App Store Connect and the domain is bought. Check again right before both.

## iOS app version 1

### Milestones

Each milestone goes to TestFlight and is used in real workouts before the next one starts.

| Milestone | Scope | Done when |
|---|---|---|
| **M1 Logging** | Sign-in, profile, workout logging (works offline), history, templates | A full gym session can be logged without a connection |
| **M2 Health and progress** | Read sleep, HRV, resting HR and workout heart rate; write workouts to Apple Health; charts; personal records | Each exercise shows its progress, and workouts appear in Apple Fitness |
| **M3 AI coach** | Next-session suggestion with its reason, weekly summary, StoreKit 2 subscription | A subscriber gets suggestions end to end. **Then submit to the App Store** |

Status (2026-10-25): the code for M1 and M2 is merged. TestFlight and testing on a real iPhone wait for the Apple Developer account. M3 is next.

### Screens

1. **Onboarding**: Clerk sign-in (email code, Google, Apple); short profile (kg or lb, experience, goal; height and birthday optional); an explanation page, then the HealthKit permission prompt.
2. **Today**: start a workout (empty or from a template); readiness card (M2); AI suggestion card or the subscription offer (M3).
3. **Workout logging** (the core screen):
   - Add exercises by search, equipment or muscle, or create a custom one (a specific machine).
   - One row per set, **prefilled with last time's load and reps** and labelled "Last: 60 kg × 8".
   - Completing a set **starts the rest timer**, which notifies even when the phone is locked.
   - Optional RIR; warm-up sets can be marked.
   - Finishing shows a summary: total volume and new personal records. From M2 the workout is written to Apple Health.
4. **History**: workouts by date; view, edit and delete.
5. **Exercise detail** (M2): all past sets, estimated one-rep max chart, personal records.
6. **Progress** (M2): body-weight trend from Apple Health, weekly sets per muscle group.
7. **Templates**: built-in templates from [coaching.md](coaching.md) and the user's own.
8. **Settings**: units, language, Apple Health, subscription, privacy policy, sign out, delete account.

Not in version 1: Apple Watch app, Live Activities and widgets, iPad layout, social features, nutrition, coach chat and plan generation.

### M1 decisions

Agreed before M1 started:

| Topic | Decision |
|---|---|
| Navigation | Four tabs: Today, History, Templates, Settings |
| Account | Sign-in is required. After sign-in the app works offline |
| Exercise search | Fuzzy, on the phone: typos, English and Chinese names, aliases (RDL, OHP, 卧推) and pinyin (`wotui`, `wt`). Results show the catalog name, with the alias that matched. The last row always offers "Create exercise" with the typed name. Aliases live in the backend catalog |
| Rest timer | 3 minutes for compound lifts, 90 seconds for isolation, editable per exercise; a local notification when the phone is locked. Without a field for it in the catalog, an exercise counts as compound when it trains three or more muscles, two primary ones, or the quads with the glutes |
| Supersets | In the data model, not in the M1 interface |
| Built-in templates | The four in [coaching.md](coaching.md), in English and Chinese |
| Progression | None in M1: sets are prefilled with last time's load and reps. Suggestions come with the coach in M3 |
| Units | Stored in kg. Shown in lb when chosen. The + and − buttons move by 2.5 kg or 5 lb (1.25 kg or 2.5 lb per dumbbell or side); typed weights are kept as typed |
| Hardware | The simulator during development; Apple Developer Program and TestFlight at the end of M1 for a real gym session |
| CI | A macOS runner builds the app and runs the Swift tests on every pull request |

M1 ships as six pull requests: project skeleton (sign-in, generated API client, tabs, CI); local store, sync and catalog; workout logging; history; templates; settings, profile and localization.

### M2 decisions

Agreed before M2 started:

| Topic | Decision |
|---|---|
| Navigation | A fifth tab, Progress |
| Without Apple Health | Everything works without a Watch and without Health access: charts and records come from logged workouts, and body weight can be typed in |
| Asking for access | An explanation page once the profile exists, then Apple's permission sheet. "Not now" keeps it in Settings |
| First import | The last 90 days, then what changed since the last import (the last two days are always read again) |
| Body weight | The latest weight from Apple Health is shown with its date and the question whether it is current. If it isn't, or there is none, the user types it in. Typed weights are written back to Apple Health |
| Readiness | Last night's sleep, HRV and resting heart rate, each compared with the user's own 28-day average. No combined score |
| Workouts to Apple Health | Written when the workout is finished, as traditional strength training. When a Watch recorded it, active energy and average and maximum heart rate for the workout's time are added |
| Weekly sets | Per muscle: a primary muscle counts 1, a secondary one 0.5. A light reference band of 10 to 20 sets |
| Personal records | Heaviest weight, best estimated one-rep max, and most reps at a weight |

M2 ships as five pull requests: Apple Health groundwork (permission, import, sync of readiness and body weight); workouts written to Apple Health; exercise detail; the Progress tab; the readiness card on Today.

### Languages

- English and Chinese (Simplified). iOS picks the language from the phone's language list, not from the App Store region.
- Users can change it per app in iOS Settings; the app's Language row opens that page instead of offering its own switcher.
- The AI coach answers in the app's current language.
- App Store listings (name, description, screenshots) are written for each language.
- **Not offered in the mainland China App Store** in version 1. Generative AI features need regulatory approval there, and the Claude API is not available there. Chinese-speaking users in other regions use the Chinese version.

### Technical choices

- SwiftUI and Swift Charts, **minimum iOS 18**.
- Adaptive layouts (size classes, no fixed sizes) so the folded and unfolded **iPhone Duo** both work. Side-by-side layouts for the unfolded screen can come later.
- Offline first: SwiftData on the phone, synced with the API when online (see "Sync on the phone" below).
- Clerk iOS SDK; API client generated from the OpenAPI document (swift-openapi-generator).
- Code lives in `ios/`: the app (`IronSage/`) and a Swift package (`IronSageKit/`) with the generated API client and the logic that `swift test` covers without a simulator. CI builds and tests it on a macOS runner.
- Needs an Apple Developer Program membership (99 USD a year) from TestFlight onwards.

### Sync on the phone

`IronSageStore` keeps each record (exercise, workout, template, profile) as the JSON of the app's own type in one SwiftData table, and loads everything into memory at launch. Every edit is saved there first and marked pending.

A sync, run at launch, when the app returns to the foreground and after a workout:

1. **Push**: each pending record goes up whole (`PUT`, or `DELETE`), exercises before the templates and workouts that use them. An edit made while its request runs stays pending. A deletion is always sent, even for a record that looks new (a 404 counts as done). A record the API rejects for good (400, 403, 404, 409, 422) stops being retried and stays on the phone, so it cannot block the others; 401, 429 and 5xx stop the sync until next time.
2. **Pull**: `GET /v1/sync?since=N` page by page; the cursor is saved after each page. A record with unsent local edits keeps the local version, which replaces the server's on the next push (last write wins).
3. **Catalog**: the built-in exercises are fetched once a day. Exercises that leave the catalog, or that a user deletes, stay readable so old workouts keep their names.

A sync requested while one runs starts again when it ends. The phone keeps only the signed-in user's data: signing out, or another user signing in, removes it, and a sync still running for the previous user stops without writing.

## Target architecture

```text
iPhone app (SwiftUI)
  ├─ Clerk iOS SDK ─────────────────► Clerk
  ├─ HealthKit (read sleep, HRV, resting HR, workout HR; write workouts)
  ├─ StoreKit 2 ────────────────────► App Store
  ├─ local store (SwiftData), syncs when online
  └─ HTTPS + Clerk token
        │
        ▼
API Lambda (FastAPI, /v1) ──────────► Neon Postgres
  │                                     ▲
  │ enqueue                             │
  ▼                                     │
SQS ──► worker Lambda ──────────────────┤──► Claude API
          ▲                             │
EventBridge Scheduler (weekly summary)  │
                                        │
Coach Lambda (streaming, longer timeout)┘──► Claude API
App Store Server Notifications V2 ─► API Lambda (subscription state)
APNs ◄── worker Lambda (weekly summary push)
Sentry ◄── app and Lambdas (errors)
```

The web app (Vercel) uses the same API and Clerk instance.

## Data model (version 1)

Built in `backend/models.py` (migration `0002`).

```text
users                 id, clerk_user_id, email, created_at, change_seq (per-user sync counter)
profiles              birthday, height_cm, gender, training_location, unit_system (metric or imperial),
                      experience_level, goal, training_days_per_week
exercises             name_en, name_zh, equipment, load_type, primary and secondary muscles,
                      aliases (search names, migration 0004), base_exercise_id (custom exercise →
                      built-in one), owner (null = built-in)
workouts              title, started_at, ended_at, time_zone, notes, average and max heart rate,
                      healthkit_workout_id, template_id
workout_exercises     workout, exercise, position, notes, superset group, rest seconds
sets                  position, type (warm-up, working, drop, failure), reps, weight_kg (3 decimals),
                      rir, duration_seconds, completed_at (null = planned)
templates             name_en, name_zh, level, days_per_week, owner (null = built-in)
template_days         template, position, name, name_zh (built-in days, migration 0005)
template_exercises    day, exercise, position, rest seconds, superset group
template_sets         position, type, rep_min, rep_max, target_rir
body_measurements     measured_at, kind (weight, body_fat, waist, ...), value, source, healthkit_sample_id
daily_readiness       date (local), sleep minutes and stages, HRV (SDNN), resting HR, source
```

Synced records (exercises, workouts, templates, body measurements, readiness, profile) carry `updated_at`, `deleted_at` (soft delete) and `change_seq`.

Added with the AI coach (P1): `recommendations`, `ai_usage`, `subscriptions`.

Notes:

- **Machines differ by brand**, so a user can add their own exercise ("Hammer Strength chest press") linked to a built-in one. Loads are only compared within the same exercise, while volume per muscle still counts it as a chest press.
- **Load types**: `total` (barbell, machine stack), `per_side` (one dumbbell, cable handle or lever arm), `bodyweight_plus` (added weight on pull-ups or dips) and `assisted` (assistance, where more is easier). Progress and suggestions depend on this.
- **Offline logging**: the app creates records with its own UUIDs and saves each workout as a whole (`PUT`, safe to retry; last write wins). Every write takes the next value of the user's `change_seq`. The update locks the user's row until commit, so `GET /v1/sync?since=N` never skips a change, and users never wait for each other.
- **History instead of snapshots**: weight, body fat and sleep live in dated tables, so trends can be charted.
- **Derived values are not stored**: personal records, estimated one-rep max and weekly sets are computed from sets.
- **Exercise catalog**: 145 exercises written for IronSage in `backend/catalog.py` (wger's data is CC BY-SA, so it was not imported). Deploys sync it to the database; ids come from the slug, and removed entries are soft-deleted so old workouts keep them.
- **Built-in templates**: the four programs from [coaching.md](coaching.md) in `backend/template_catalog.py`, synced the same way after the exercises.

## AI coach

### Next-session suggestion

1. **Rules (deterministic, unit-tested)**
   - Estimated one-rep max (e1RM) from recent sets.
   - Double progression: when every working set reaches the top of the rep range, add load next time.
   - Trend for each exercise over the last sessions.
   - The rules follow [coaching.md](coaching.md).
2. **Claude adjusts and explains**
   - Input: the rule-based plan, recent sessions, and readiness (sleep, HRV and resting HR compared with the user's own baseline, heart rate in the last session).
   - Output: the final suggestion and a short reason. Example: "You slept 5.5 h and HRV is 20% below your usual, so keep 60 kg instead of adding weight."
3. **Stored** in `recommendations` with the inputs, so the user and we can see later why a suggestion was made.

Later (version 2), a coach agent can chat and change plans with tools on our API. Tools are read-only by default. Any write (for example changing a plan) needs the user's confirmation. User-written text (notes, exercise names) is treated as data, never as instructions, to guard against prompt injection.

### Runtime

- The current API Lambda has a 15 s timeout and Mangum buffers responses, so AI calls run elsewhere:
  - **Coach Lambda** for interactive calls: streams responses (AWS Lambda Web Adapter) and has a longer timeout.
  - **SQS + worker Lambda** for jobs nobody waits for (weekly summary), started by **EventBridge Scheduler**.
- Every AI endpoint checks the subscription first. Without one it returns `402 Payment Required`.
- Each user has a daily AI quota. `ai_usage` records tokens so costs can be watched.
- Model choice, prices and rate limits are checked against Anthropic's current documentation when this is built, not from memory.

### Evaluation

- Rules: ordinary unit tests.
- Claude step: a fixed set of example users and sessions, with checks on output format, safe load changes (no large jumps) and whether the explanation refers to the actual data.

## Apple Health

- Only the iPhone can read HealthKit, so the app reads it and uploads **daily summaries** (sleep, HRV, resting HR, workout heart rate). Raw samples are never uploaded.
- Finished workouts are written to HealthKit so they appear in Apple Fitness.
- Before anything is sent to the AI, the app tells the user which summaries are sent and asks for consent. HealthKit data is never used for advertising (an App Store rule).

## Subscriptions

**Version 1 uses StoreKit 2 only.**

- Apple handles payment, taxes, refunds, free trials and cancellation. Under the Small Business Program the commission is 15%.
- The app sends the signed transaction to the API. **App Store Server Notifications V2** tell the API about renewals, refunds and cancellations. The API keeps one entitlement per user in `subscriptions`.
- Stripe web checkout is **postponed**. Since the Epic v. Apple ruling, US apps may link to web checkout. A court is still deciding what commission Apple may charge on those purchases, and the Supreme Court is reviewing part of the case. Revisit Stripe when that rate is settled. Because the API only checks the entitlement, a second payment source can be added without changing the AI endpoints.

## API conventions

- One OpenAPI document (generated by FastAPI) is the contract. The Swift client and TypeScript types are generated from it.
- Lists are paginated and accept date ranges.
- Timestamps include a time zone.
- Errors use one shape: `{"detail": "..."}`.

## Privacy

- Weight, body fat, sleep and heart rate are health data. A privacy policy and a "what is sent to AI" explanation must exist before the App Store submission.
- Health data never appears in analytics events or logs.
- Account deletion (`DELETE /v1/me`) removes all of a user's rows. Stored files (for example progress photos, if added) must be deleted too.

## Roadmap for the architecture

### P0: before the iOS app

1. ~~**Alembic** for database migrations~~. Done: migrations run automatically during each deploy (see [deployment.md](deployment.md)).
2. ~~**Data model version 1**~~. Done: strength sets, a 145-exercise catalog written for IronSage (wger's data is CC BY-SA, so it was not imported), templates, dated body and readiness tables. Old workouts and profiles were dropped.
3. ~~**Offline sync support**~~. Done: client UUIDs, soft deletes, a per-user `change_seq` and `GET /v1/sync`.
4. ~~**API conventions**~~. Done: pagination, date filters, time zones, and `api/openapi.json` as the contract with readable operation ids. The web generates TypeScript types from it; the iPhone app will use swift-openapi-generator with the same file.
5. ~~**Privacy policy** and AI data consent text~~. Done: [ironsage.app/privacy](https://ironsage.app/privacy) and [/support](https://ironsage.app/support) in English and Chinese, and the app's consent screens in [consent-copy.md](consent-copy.md). Have the policy reviewed before the App Store submission.

### P1: before the AI coach

6. Coach Lambda with streaming and a longer timeout.
7. SQS, worker Lambda and EventBridge Scheduler for weekly summaries.
8. StoreKit 2 entitlement, App Store Server Notifications V2, `402` on AI endpoints, daily AI quota.
9. `recommendations` table and AI evaluation set.
10. Sentry and CloudWatch alarms (5xx errors, cost).

### P2: before public launch

- Clerk production instance (needs an owned domain) with our own Google and Apple sign-in credentials.
- Staging environment on a Neon branch.

## Features and integrations

### Version 1

| Feature | External integrations |
|---|---|
| Sign-in | Clerk |
| Strength logging, rest timer, templates | None (exercise catalog seeded from wger; templates from [coaching.md](coaching.md)) |
| Sleep, heart rate, workout sync | Apple HealthKit (read and write) |
| Progress charts, personal records | None (Swift Charts) |
| AI coach: next-session suggestion, weekly summary (paid) | Claude API, StoreKit 2, App Store Server Notifications V2, AWS SQS, EventBridge Scheduler |
| Notifications | Local notifications; APNs for the weekly summary |
| Error monitoring | Sentry |

### Version 2

| Feature | External integrations |
|---|---|
| Nutrition logging | USDA FoodData Central, Open Food Facts (barcodes), Claude vision for meal photos |
| Coach chat and plan generation (agent) | Claude API with tool use |
| Web subscription (US) | Stripe, once Apple's link-out commission is settled |
| Weekly summary email | Resend, Postmark or AWS SES (needs an owned domain) |

## What to revisit as TrainWise grows

- **Lambda limits**: if sync or AI traffic grows a lot, look at provisioned concurrency or a container service.
- **Neon cold starts**: the database scales to zero; the first request after idle is slower. A paid plan can keep it warm.
- **Exercise catalog**: user-created exercises may need merging or moderation.
- **More health sources**: direct Oura, Whoop or Garmin APIs if many users rely on them outside HealthKit.
