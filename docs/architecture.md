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
| Navigation | Five tabs: Today, History, Progress, Templates, Me (the profile, training and body at a glance, the coach plan and the account) |
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

### M3 decisions

Agreed on 2026-10-25:

| Topic | Decision |
|---|---|
| Free and paid | The rule-based weights and reps are free. The AI's reasons, its readiness adjustments and the weekly summary need the subscription |
| Where the rules run | On the phone (`IronSageCore/NextSession.swift`), so suggestions work offline and cost nothing |
| When the AI runs | Ahead of time: after a workout syncs, and in the morning once last night's sleep is in. The result is stored and shown offline; nobody waits for it, so no streaming Lambda is needed |
| What the AI may change | Only one of three actions per exercise: follow the rule plan, hold the weight, or one set fewer. The backend turns the action into sets, so the model never writes a weight |
| AI provider | Not tied to one: a small adapter per provider (Claude, Gemini, OpenAI). **Claude Sonnet 5.5** runs in production, chosen on 2026-10-25 from the eval (Opus, Sonnet and Haiku 5.5 all chose correctly in every case; Sonnet costs about $0.007 per suggestion, about 2.8 s). Changing provider also means updating the privacy policy, the consent text and the App Store privacy label |
| Price | $4.99 a month or $39.99 a year, with a 7-day free trial for new subscribers. One auto-renewable group "IronSage Coach": `app.ironsage.coach.monthly` and `app.ironsage.coach.yearly` (yearly ranks higher, so switching to it takes effect at once) |
| Margin | About 50%. After Apple's 15% (Small Business Program) monthly nets about $4.24 and yearly about $2.83 a month, so everything a subscriber costs (AI, Lambda, database) stays under about $1.40 a month |
| Who decides access | The API, from the signed transaction it verified (`402` without one). The phone's StoreKit state only decides what the screens offer. `users.coach_enabled` stays as a manual override for test accounts |
| Promotion codes | Apple's subscription offer codes, redeemed with StoreKit's sheet ("Redeem code" on the paywall and in Settings). The resulting transaction reaches the API like a purchase; its offer type and id are stored |
| Receipt checks | Offline: the JWS chain is checked against Apple Root CA - G3 in the code, so no App Store Connect API key is needed. Calling the App Store Server API (for example to look up a transaction) can come later |
| Weekly summary | Every Monday 06:00 Los Angeles time, for the last full week in each user's own time zone. The backend computes the numbers from synced data; the model only words them, in the language the app reported. Only for users with coach access who turned the coach on in the app (the app tells the server). Under one cent each. No push notification until the Apple Developer account exists |
| Agent | Not in M3. A chat coach with tools comes after the US launch |
| Markets | US App Store first. Mainland China later; it needs a mainland filing entity, a China-hosted backend, a filed domestic model and its own sign-in |

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
  │ starts without waiting              │
  ▼                                     │
Coach worker Lambda ────────────────────┘──► Claude API
  ▲   └─ starts itself once per user for the weekly summary
EventBridge Scheduler (Monday 06:00 Los Angeles)
App Store Server Notifications V2 ─► API Lambda (subscription state)
APNs ◄── coach worker Lambda (weekly summary push, later)
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

Added with the AI coach (P1): `recommendations` (migration 0006), `subscriptions` (0007; one row per user: product, `expires_at`, original and latest transaction id, environment, status), `weekly_summaries` and `users.coach_consent` / `coach_language` (0008), `ai_usage`.

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
2. **The AI adjusts and explains** (`backend/coach/`)
   - Input: the rule-based plan, the last few sessions of each exercise, and readiness (sleep, HRV and resting HR compared with the user's own baseline).
   - Output: for each exercise one action (follow, hold the weight, one set fewer) and a one-sentence reason, plus a one-line summary. Example: "You slept 5 h 10 min, so stay at 100 kg today." `coach/guardrails.py` applies the actions; advice that doesn't match the plan is rejected and the app keeps the rule plan.
   - Instructions are Markdown skills in `coach/skills/` (safety, next session), loaded by task. They work the same with every provider.
3. **Stored** in `recommendations` with the inputs, so the user and we can see later why a suggestion was made.

### Weekly summary

Every Monday morning each subscriber who turned the coach on gets a short recap of their past week, on Today and in Progress.

1. **The numbers come from the backend** (`backend/weekly.py`), from the workouts and readiness the phone synced, with the same rules the phone uses: completed working sets per muscle (secondary muscles 0.5) against the 10–20 reference band, new records (heaviest weight or best estimated one-rep max, beating every earlier session), lifts stalled across their last three sessions, and the week's sleep, HRV and resting heart rate against the 28 days before. A lighter week (deload) is suggested by the rules when two or more lifts stalled or four or more nights were short (under 6 hours, or an hour below usual), never from HRV or resting heart rate.
2. **The model only words them** (skill `coach/skills/weekly_summary.md`): 3–5 sentences, one or two suggestions for the coming week, and `deload`. `coach/guardrails.check_week` rejects a lighter week the rules didn't suggest (the flag or its words), and answers without suggestions or with more than two.
3. **The job** (`coach_handler.start_weekly_summaries`): EventBridge Scheduler starts the coach worker every Monday at 06:00 Los Angeles time (09:00 New York) with `{"job": "weekly_summaries"}`. For each user who turned the coach on in the app and has access (`routers/subscription.has_coach_access`, the same check as the API's), it takes the last full Monday-to-Sunday week in the time zone of their latest workout, stores a pending summary with its input, and starts the worker once more for it, which works like a recommendation (claim, no open transaction during the model call, fixed error codes) and checks access and consent again before asking the model. One summary per user and week (a unique constraint), so a retried job never pays twice; a summary left pending for 5 minutes is started again by the next run. With 15 s of its 60 s left, the job starts itself again to go on with the remaining users. Users without a finished workout that week get none.
4. **Delivered through sync** as `weekly_summaries` in `GET /v1/sync`. The phone shows last week's summary once it is ready, and nothing for a week without one.
5. **Consent on the server**: the server writes the summary on its own, so the app tells it whether the coach is on, and its language (`PUT /v1/coach/settings`), when the user turns it on or off and at launch, and turns it off before signing out and for the next account after a sign-out. Turning it off stops the next summary once the phone has synced; a phone that stays offline until Monday morning still gets that week's.

Cost, estimated from the prompt size until the eval has run: a summary is about 1,200–1,500 input and 250–350 output tokens, **$0.005–0.007** on Sonnet 5.5, so about $0.03 per subscriber a month, well inside the $1.40 budget. Measure it with `python scripts/coach_eval.py anthropic:claude-sonnet-5-5 --task weekly_summary`.

Later (version 2), a coach agent can chat and change plans with tools on our API. Tools are read-only by default. Any write (for example changing a plan) needs the user's confirmation. User-written text (notes, exercise names) is treated as data, never as instructions, to guard against prompt injection.

### Runtime

- The current API Lambda has a 15 s timeout and Mangum buffers responses, so AI calls run elsewhere. Nobody waits for them (see M3 decisions), so one **coach worker Lambda** (`trainwise-coach-prod`, 60 s) does both:
  - **Next-session suggestions**: the API stores the request and starts the worker without waiting.
  - **Weekly summaries**: **EventBridge Scheduler** starts it on Monday morning; it starts itself once per user, and again to go on with the job when its 60 s run short. No SQS: Lambda's own queue for asynchronous calls is enough at this size. Before many hundreds of subscribers, spread the runs out (an SQS queue with a concurrency limit), since they all reach the provider's rate limit at once.
- Every AI endpoint checks access first (`routers/subscription.has_coach_access`). Without it it returns `402 Payment Required`.
- Each user has a daily AI quota. `ai_usage` records tokens so costs can be watched.
- Model choice, prices and rate limits are checked against each provider's current documentation when this is built, not from memory.

### Evaluation

- Rules: ordinary unit tests.
- AI step: `coach/eval_cases.py` holds example users: 12 next-session scenarios and 9 weekly-summary scenarios, each in English and Chinese. `scripts/coach_eval.py` runs them against real models and reports, per model, how many passed, the cost per suggestion and the time. A case fails on: no usable JSON, an action the coaching rules don't allow there (for example adding weight after a short night, or changing the plan for low HRV alone), a weight above the rule plan, the wrong language, a number that isn't in the input, or repeating instructions hidden in an exercise name. A weekly summary also fails with fewer than 3 or more than 5 sentences, or a lighter week that doesn't match the rules (including one suggested for low HRV alone). Run it with `--task weekly_summary`.

## Apple Health

- Only the iPhone can read HealthKit, so the app reads it and uploads **daily summaries** (sleep, HRV, resting HR, workout heart rate). Raw samples are never uploaded.
- Finished workouts are written to HealthKit so they appear in Apple Fitness.
- Before anything is sent to the AI, the app tells the user which summaries are sent and asks for consent. HealthKit data is never used for advertising (an App Store rule).

## Subscriptions

**Version 1 uses StoreKit 2 only.**

- Apple handles payment, taxes, refunds, free trials and cancellation. Under the Small Business Program the commission is 15%.
- The app sends the signed transaction to the API. **App Store Server Notifications V2** tell the API about renewals, refunds and cancellations. The API keeps one entitlement per user in `subscriptions`.

How it is built:

- **Phone** (`ios/IronSage/Coach/SubscriptionService.swift`): StoreKit 2. `Product.products` loads both plans, `purchase()` buys, `AppStore.sync()` restores, `Transaction.currentEntitlements` says whether this Apple Account is subscribed and `Transaction.updates` brings renewals, refunds and Ask to Buy approvals. Every verified transaction's JWS goes to `PUT /v1/subscription` (once per transaction; again after a restore), including the one a redeemed offer code produces. Once the server has answered, its `coach_access` decides what the screens offer; before that (or offline) the App Store entitlement does. When the App Store says subscribed but the server doesn't, Today offers to confirm the subscription (a restore) instead of the paywall. The paywall (`PaywallView.swift`) follows the coach consent sheet when there is no subscription, and is offered on Today when the coach answers `402` and in Settings. It shows the price, the trial, the renewal terms (App Store Review Guideline 3.1.2), Restore purchases, Apple's standard Terms of Use and the privacy policy.
- **API** (`backend/appstore.py`, `backend/routers/subscription.py`):
  - `PUT /v1/subscription` verifies the JWS (ES256; the `x5c` chain must lead to Apple Root CA - G3 and carry Apple's marker extensions, and every certificate must have been valid when the data was signed), then checks the bundle id `app.ironsage.IronSage`, the two product ids and the type. It stores product, `expires_at`, original and latest transaction id, when Apple signed that copy, environment (Production or Sandbox, which App Review and TestFlight use), status and the offer used (free trial, offer code with its id, promotional or win-back). A different transaction that ends earlier than the stored one is ignored, and so is an older copy of the stored transaction, so a late or replayed one never shortens access, and a copy saved before a refund never brings access back.
  - One original transaction id belongs to one IronSage account (`409` for another), so one purchase can't unlock several accounts. Deleting the account only unlinks the row (`user_id` null, no personal data), so the same Apple Account can link it to a new IronSage account but a refunded purchase stays refunded. The App Store subscription itself is cancelled by the user in Settings.
  - `POST /v1/app-store/notifications` takes App Store Server Notifications V2 without sign-in, verifies them the same way and applies the signed transaction and renewal info: renewals extend `expires_at`, the billing grace period is stored separately (`grace_period_expires_at`, so the phone resending the lapsed transaction doesn't cut it short) and access lasts until the later of the two, expiries and refunds end access, a refund reversal brings it back. Notifications for a subscription no account has claimed yet are ignored, because the phone sends it anyway.
  - `GET /v1/subscription` returns the status and `coach_access` (subscription or manual override).
  - Access is checked when the coach is asked (`PUT /v1/recommendations/{id}`): an active subscription (`expires_at` in the future and not refunded) or `users.coach_enabled`.
- **Testing without an Apple Developer account**: the scheme runs the app with `ios/IronSage.storekit`, so buying, the trial, renewals, expiry and refunds work in the simulator (Debug › StoreKit › Manage Transactions in Xcode; Editor › Subscription Renewal Rate speeds renewals up). It has a sample offer code per plan for trying "Redeem code": `COACHYEAR50` (first year $19.99) and `COACHMONTH50` (first three months $2.49). Real codes are created in App Store Connect. Those transactions are signed by Xcode, not Apple, and the API refuses them unless it runs locally with `APP_STORE_ACCEPT_XCODE=1` (ignored on Lambda). `ios/IronSageTests` runs the same purchase, restore, expiry and refund steps with `SKTestSession` (Product › Test in Xcode, or `xcodebuild test`). On the iOS 27.1 simulator `xcodebuild test` doesn't hand the configuration to the simulator's StoreKit (an Xcode issue), so run them on an iOS 18 simulator from the command line.
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
7. ~~Worker Lambda and EventBridge Scheduler for weekly summaries~~. Done without SQS: the coach worker starts itself once per user.
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
