# Subscription Domain Reference

## Overview

The `subscription` domain owns plan definition, user subscription lifecycle, quota consumption, free-plan fallback, and simulated subscription payments.

It is responsible for:

- defining subscription plans and their limits
- choosing a single active default free plan
- creating paid subscriptions for users
- upgrading immediately or scheduling downgrades
- renewing or replacing subscriptions when the current one expires
- enforcing consumption limits on subscription quotas
- exposing user, admin, and root plan-management APIs

This domain is implemented primarily in:

- `com.bun.platform.subscription.domain`
- `com.bun.platform.subscription.service`
- `com.bun.platform.subscription.repository`
- `com.bun.platform.subscription.controller`
- `com.bun.platform.subscription.events`

## Responsibilities

- model subscription products as `Plan`
- model time-bounded user entitlements as `Subscription`
- persist plan limits and subscription usages as JSONB
- ensure only one active default free plan exists
- prevent overlapping active subscription periods per user
- provide a free fallback when no current subscription exists
- apply a single grace extension to expired paid subscriptions
- support quota checks and usage consumption per limit type

## Package Summary

### `com.bun.platform.subscription.domain`

Contains the core domain model:

- `Plan`
- `Subscription`
- `SubscriptionStatus`
- `LimitType`
- `LimitValue`
- `UsageValue`
- `DomainException`
- `LimitExceededException`

### `com.bun.platform.subscription.service`

Contains the application services:

- `PlanService`
- `SubscriptionService`
- `SubPaymentService`

### `com.bun.platform.subscription.controller`

Contains the HTTP surface:

- `PlanController`
- `SubscriptionController`
- `SubPaymentController`

### `com.bun.platform.subscription.events`

Contains domain event record types for future or partial event-driven workflows.

## Core Model

### `Plan`

**Kind:** entity  
**Table:** `plans`

Represents a subscription product definition.

Key fields:

- `id`
- `code`
- `name`
- `price`
- `paid`
- `periodDays`
- `level`
- `trialDays`
- `defaultFree`
- `active`
- `limits`

Behavioral contract:

- `getPeriod()` returns `Duration.ofDays(periodDays)`
- `isTrial()` is true when `trialDays > 0`
- `getTrialPeriod()` returns `Duration.ofDays(trialDays)`
- `getLimit(LimitType)` exposes the optional configured limit

Persistence notes:

- soft delete through Hibernate `@SoftDelete`
- `limits` stored as JSONB map from `LimitType` to `LimitValue`
- unique `code`
- DB migration enforces a single `default_free = true` row via partial unique index

### `Subscription`

**Kind:** entity  
**Table:** `subscriptions`

Represents a time-bounded entitlement for a user on a specific plan.

Key fields:

- `id`
- `userId`
- `plan`
- `status`
- `startAt`
- `endAt`
- `deletedAt`
- `usages`
- `createdAt`
- `updatedAt`
- `graceAppliedAt`
- `lastRenewedAt`
- `nextPlanId`

Behavioral contract:

- `isGraced()` returns whether grace was already applied
- `isDeleted()` reflects soft deletion through `deletedAt`
- `isExpired(now)` checks `endAt <= now`
- `isCurrentlyValid(now)` requires:
  - not deleted
  - `startAt <= now`
  - `endAt > now`
- `canConsume(type, amount)` validates time validity and configured limit
- `consume(type, amount)` increments usage or throws `LimitExceededException`
- `resetUsages()` resets all tracked usages to zero
- `softDelete()` timestamps `deletedAt`
- `markRenewedAt(now)` updates `lastRenewedAt`

Design note:

- `nextPlanId` is used to remember a desired future plan change at period end
- `next_subscription_id` exists in the migration but is not mapped in the entity

### `SubscriptionStatus`

Current status values:

- `FREE`
- `TRAIL`
- `PAID`
- `PAY_PENDING`

Implementation note:

- the enum literal is spelled `TRAIL` in code and database checks, not `TRIAL`

### `LimitType`

Current limit dimensions:

- `PRODUCTS`
- `ORDERS`
- `STORAGE_MB`

### `LimitValue`

Value object stored inside `Plan.limits`.

Key field:

- `max`

Behavioral contract:

- `max = null` means unlimited
- `canConsume(used, amount)` returns whether the requested amount fits
- `of(max)` rejects negative values
- `unlimited()` returns an unlimited limit

### `UsageValue`

Value object stored inside `Subscription.usages`.

Key field:

- `used`

Behavioral contract:

- `zero()` initializes usage at zero
- `add(amount)` and `increment(amount)` reject non-positive values
- `reset()` zeroes usage

## Services

### `PlanService`

Owns plan lifecycle and plan-level business validation.

Key operations:

- `listAll()`
- `getByCode(String)`
- `getById(long)`
- `create(CreatePlanRequest)`
- `createAndChangeDefaultFree(CreatePlanRequest)`
- `changeDefaultFreePlan(Long)`
- `update(long, UpdatePlanRequest)`
- `unActivate(long)`
- `getDefFreePlan()`
- `getByIdAndActiveTrue(Long)`

Important rules:

- plan code must be unique
- paid plans must have `price > 0`
- free plans must have `price = 0`
- trial plans must also be paid plans with `price > 0`
- default free plans must be free and non-trial
- deactivating the active default free plan is not allowed

Operational behavior:

- changing default free deactivates the previous default free plan
- limits are normalized so null values become unlimited
- all writes evict `plan_cache`

### `SubscriptionService`

Owns subscription lifecycle, free fallback, grace handling, and usage consumption.

Key operations:

- `getAllSubscriptions(Long)`
- `purchasePlan(Long, Long)`
- `upgradeOrSameNow(Long, Long)`
- `downgradeLater(Long, Long, Long)`
- `cancelSubscription(Long)`
- `consume(Long, LimitType, long)`
- `getCurrentOrGoFree(Long)`

Important rules:

- no overlapping active periods are allowed for a user
- admin purchases create immediate `PAID` subscriptions
- upgrades terminate current and future non-deleted subscriptions by soft delete, then create a fresh `PAID` subscription from now
- scheduled downgrade sets `nextPlanId` on the current valid subscription
- cancel marks the current effective subscription as deleted
- consumption always targets `getCurrentOrGoFree(userId)`

Fallback algorithm in `getCurrentOrGoFree(userId)`:

1. Return current valid non-deleted subscription if found.
2. Otherwise inspect the latest non-deleted subscription.
3. If latest is `PAID` and expired:
   - apply a one-time 2-day grace extension
   - change status to `PAY_PENDING`
   - publish `PayPendingSubscription`
4. If latest is `FREE` and expired:
   - renew it in place
   - reset usages
5. If nothing suitable exists:
   - create a fresh subscription from the active default free plan

Implementation notes:

- a number of event record types exist, but current service code only publishes `PayPendingSubscription`
- `purchasePlan(...)` sets `nextPlanId` to the current purchased plan ID, even though the field is documented as a future plan change marker

### `SubPaymentService`

Current payment integration stub.

Current behavior:

- `charge(Subscription)` always returns `false`
- intended to be replaced later by Stripe/Visa or equivalent integration

## Repository Surface

### `PlanRepository`

Provides:

- `findByCode(String)`
- `findFirstByDefaultFreeTrue()`
- `existsByDefaultFreeTrue()`
- `existsByDefaultFreeAndActive(boolean, boolean)`
- `findByDefaultFreeTrueAndActiveTrue()`
- `findByIdAndActiveTrue(Long)`

### `SubscriptionRepository`

Provides:

- `findByIdAndUserId(Long, Long)`
- `findByUserIdOrderByStartAtDesc(Long)`
- `existsByUserIdAndDeletedAtIsNullAndStartAtGreaterThan(Long, Instant)`
- `findByUserIdAndDeletedAtIsNullAndEndAtGreaterThan(Long, Instant)`
- `findCurrentByUserId(Long)`
- `findLatestByUserId(Long)`
- `checkOverlap(Long, Long, Instant, Instant)`
- `existsByPlanId(Long)`

Important details:

- current and latest lookups are native SQL queries
- overlap checks are duplicated at two levels:
  - repository-level boolean query
  - database exclusion constraint on `(user_id, tstzrange(start_at, end_at))`

## HTTP Surface

### Plan API

Base path: `/api`

Public endpoints:

- `GET /api/public/plans`
- `GET /api/public/plans/{code}`

Root-only endpoints:

- `POST /api/admin/plans`
- `PATCH /api/admin/plans/{id}`

### Subscription API

Base path: `/api/subscriptions`

User endpoints:

- `GET /current`
- `POST /cancel`
- `POST /consume?type=...&amount=...`

Admin/root endpoints:

- `GET /admin/users/{userId}` with `ROLE_ROOT`
- `POST /admin/purchase?userId=...&planId=...` with `ROLE_ADMIN`
- `POST /admin/upgrade?userId=...&planId=...` with `ROLE_ADMIN`
- `POST /admin/downgrade?userId=...&planId=...&oldSubId=...` with `ROLE_ADMIN`

Identity resolution:

- controller first tries JWT claim `uid`
- falls back to `public_uid`
- when `public_uid` is used, it resolves the local user ID through `UserIdentityService`

### Subscription Payment API

Base path: `/api/sub-payments`

Admin endpoint:

- `POST /{subscriptionId}/charge`

Response:

- `{ "success": false }` in the current stub implementation

## Exception Handling

### English

- Subscription errors should use the bilingual platform envelope with stable business error codes so plan management, billing, and quota consumers can react deterministically.
- `400 Bad Request`: use for invalid plan definitions, invalid consume amounts, malformed upgrade or downgrade requests, or requests that fail basic subscription validation before state transition.
- `404 Not Found`: use when the target plan or subscription cannot be found.
- `409 Conflict`: use for duplicate plan codes, overlapping subscription periods, invalid downgrade timing, attempts to deactivate the default free plan, or quota exhaustion represented by `LimitExceededException`.
- `403 Forbidden`: use when user, admin, or root-only plan-management actions are invoked without the required authority.
- `503 Service Unavailable`: prefer this when a billing dependency or payment gateway is unavailable and the subscription action cannot be completed safely.
- `500 Internal Server Error`: reserve for unexpected orchestration failures, event-publication failures, or runtime errors that are not mapped to domain outcomes.
- Current implementation note: `DomainException` and `LimitExceededException` are real domain exceptions in the code, but they are not yet explicitly mapped by `GlobalExceptionHandler`; professional handling should normalize them instead of letting them fall to generic `500` behavior.

### العربية

- يجب أن تستخدم أخطاء الاشتراكات غلاف الأخطاء ثنائي اللغة مع رموز أخطاء أعمال ثابتة حتى تستطيع إدارة الخطط والفوترة ومستهلكات الحصص التعامل معها بشكل حتمي.
- `400 طلب غير صحيح`: يستخدم عند وجود تعريف خطة غير صالح، أو كمية استهلاك غير صحيحة، أو طلبات ترقية أو خفض مشوهة، أو طلبات تفشل في التحقق الأساسي قبل تغيير الحالة.
- `404 غير موجود`: يستخدم عندما لا يمكن العثور على الخطة أو الاشتراك المطلوب.
- `409 تعارض`: يستخدم عند تكرار رمز الخطة، أو تداخل فترات الاشتراك، أو توقيت خفض غير صالح، أو محاولة تعطيل الخطة المجانية الافتراضية، أو استنفاد الحصة الممثل بواسطة `LimitExceededException`.
- `403 ممنوع`: يستخدم عندما يتم استدعاء عمليات إدارة الخطط الخاصة بالمستخدم أو المدير أو الجذر دون الصلاحية المطلوبة.
- `503 الخدمة غير متاحة`: يفضل استخدامه عندما تكون تبعية الفوترة أو بوابة الدفع غير متاحة ولا يمكن إكمال عملية الاشتراك بأمان.
- `500 خطأ داخلي في الخادم`: يحجز لفشل التنسيق غير المتوقع، أو فشل نشر الأحداث، أو الأخطاء التشغيلية التي لا ترتبط مباشرة بنتيجة أعمال معروفة.
- ملاحظة تنفيذية حالية: الاستثناءان `DomainException` و`LimitExceededException` يمثلان أخطاء نطاق حقيقية في الكود، لكن `GlobalExceptionHandler` لا يربطهما صراحة حتى الآن، والمعالجة الاحترافية تتطلب توحيدهما بدلاً من تركهما يسقطان إلى سلوك `500` العام.

## Persistence Summary

Migration `V16__subsicription_dom.sql` defines the schema.

Primary tables:

- `plans`
- `subscriptions`

Important columns:

- `plans.limits`: JSONB
- `subscriptions.usages`: JSONB
- `subscriptions.deleted_at`: soft-delete timestamp
- `subscriptions.grace_applied_at`
- `subscriptions.last_renewed_at`
- `subscriptions.next_plan_id`

Important constraints and indexes:

- unique `plans.code`
- partial unique index for one `default_free = true`
- period check `end_at > start_at`
- status check for `FREE | TRAIL | PAID | PAY_PENDING`
- exclusion constraint preventing overlapping active ranges per user
- current-subscription lookup index on `(user_id, end_at)` where not deleted

Seed data:

- `R__default_free_plan.sql` upserts `FREE_DEFAULT`
- default seed limits:
  - `PRODUCTS = 150`
  - `ORDERS = 50`

## Event Types

The package defines event records for:

- `SubscriptionStartedEvent`
- `SubscriptionRenewedEvent`
- `SubscriptionUpgradedEvent`
- `SubscriptionScheduledEvent`
- `SubscriptionDowngradeScheduledEvent`
- `SubscriptionCanceledEvent`
- `SubscriptionExpiredEvent`
- `SubscriptionConsumedEvent`
- `PayPendingSubscription`
- `DowngradeScheduledEvent`

Current implementation note:

- only `PayPendingSubscription` is currently published by `SubscriptionService`

## End-to-End Flows

### Get Current Subscription

1. User calls `GET /api/subscriptions/current`
2. Controller resolves user identity from JWT
3. Service returns the current valid subscription if one exists
4. Otherwise it may grace, renew free, or create a default free subscription

### Admin Purchase

1. Admin picks a user and an active plan
2. Service creates a fresh `PAID` subscription starting now
3. Overlap is checked before save
4. The new subscription is returned

### Immediate Upgrade

1. Admin chooses a new active plan
2. All current and future subscriptions ending after now are soft deleted
3. A fresh `PAID` subscription is created from now
4. Usages start from zero because this is a new row

### Grace On Expired Paid Subscription

1. No current subscription is found
2. Latest subscription is `PAID` and expired
3. Service applies a one-time 2-day extension
4. Status changes to `PAY_PENDING`
5. `PayPendingSubscription` is published

### Quota Consumption

1. Caller invokes `/consume` with a `LimitType` and amount
2. Service resolves the current effective subscription
3. `canConsume(...)` verifies time validity and limit
4. `consume(...)` increments usage or throws `LimitExceededException`

## Design Constraints And Observations

- Plans are configuration objects; subscriptions are time-bounded user facts
- Limits and usages are modeled as JSONB maps rather than normalized relational tables
- The default free plan is essential to system fallback behavior and cannot simply disappear
- Grace handling is implemented only for expired paid subscriptions, and only once
- The payment service is currently a stub, so paid renewal/payment recovery is not complete
- Several event records exist ahead of full event-driven orchestration, but most are not wired yet

## Improvement Areas

- Complete the payment workflow. `SubPaymentService` currently always fails, which leaves paid renewal and recovery incomplete.
- Wire or remove the unused event records so the event model matches the actual orchestration behavior.
- Clarify and implement scheduled renewal/downgrade semantics around `nextPlanId` and the unmapped `next_subscription_id` column.
- Revisit status naming and spelling. `TRAIL` should likely become `TRIAL` if backward compatibility permits.
- Add automated tests for overlap prevention, free fallback, grace extension, quota consumption, and admin upgrade/downgrade flows.
