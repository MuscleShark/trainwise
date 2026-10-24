# Architecture

This document describes where TrainWise is going and why. [deployment.md](deployment.md) covers how the current system is deployed.

## Positioning

TrainWise is an **iOS-first strength-training log with an AI coach**.

- **Users** lift weights. They log exercises, sets, reps and load, for example a chest press on a specific machine at a specific weight.
- **Core loop**: log a session, then before the next one the coach suggests what to do (exercise, load, sets and reps) and explains why. The suggestion uses past sessions and Apple Health data (sleep, heart rate variability, resting heart rate, heart rate during earlier workouts).
- **Business model**: logging, history and charts are free. The AI coach is a subscription.
- **Platforms**: iPhone app (main product). The web app shrinks to a landing page plus privacy and support pages. No Android.
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

```text
users                 id, clerk_user_id, email, created_at
profiles              birthday, height_cm, gender, goal, unit preference (kg/lb), experience level
exercises             name, equipment (barbell, dumbbell, machine, cable, smith, bodyweight),
                      primary and secondary muscles, owner (null = built-in catalog, else user id)
workouts              started_at, ended_at, time zone, notes, healthkit_workout_id
workout_exercises     workout, exercise, position
sets                  reps, weight_kg, rir or rpe, type (warm-up, working, drop), completed_at
body_metrics          date, weight_kg, body_fat_percentage, source (manual or healthkit)
daily_readiness       date, sleep minutes and stages, HRV (SDNN), resting HR, source
workout_heart_rate    workout, average and max heart rate
recommendations       inputs snapshot, rule-based plan, final suggestion, explanation, model, created_at
ai_usage              user, endpoint, input and output tokens, created_at
subscriptions         user, original transaction id, product, status, expires_at
```

Notes:

- **Machines differ by brand**, so a user can add their own exercise ("Hammer Strength chest press") and loads are only compared within the same exercise.
- **Offline logging**: the app creates records offline. Records that the app creates get a client-generated UUID, `updated_at` and a soft-delete flag. The API offers "changes since" queries so the app can sync.
- **History instead of snapshots**: weight, body fat and sleep move out of `profiles` into dated tables, so trends can be charted.
- The built-in exercise catalog is seeded once from [wger](https://wger.de) data (check its license before importing) and then maintained in our database.

## AI coach

### Next-session suggestion

1. **Rules (deterministic, unit-tested)**
   - Estimated one-rep max (e1RM) from recent sets.
   - Double progression: when every working set reaches the top of the rep range, add load next time.
   - Trend for each exercise over the last sessions.
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

1. **Alembic** for database migrations, instead of `create_tables.py` and one-off scripts.
2. **Data model version 1** as above (strength sets, exercise catalog, dated body and readiness tables).
3. **Offline sync support**: client UUIDs, `updated_at`, soft delete, "changes since" queries.
4. **API conventions**: pagination, date filters, time zones, generated clients.
5. **Privacy policy** and AI data consent text.

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
| Strength logging, rest timer | None (exercise catalog seeded from wger) |
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
