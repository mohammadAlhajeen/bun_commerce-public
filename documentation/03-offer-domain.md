# Offer Domain Reference

## Overview

The `Offer` domain defines catalog-level price reductions applied to product variants.

It is responsible for:

- creating seller-owned offers
- linking and unlinking offers to variants
- expanding product-level targeting into variant-level targeting
- controlling offer lifecycle states such as draft, active, suspended, and expired
- materializing the effective offer onto `VariantPrice`
- scheduled activation and deactivation processing
- choosing the best active offer when multiple offers target the same variant

Primary package:

- `com.bun.platform.catalog.offer`

Collaborating packages:

- `com.bun.platform.catalog.product`

## Package Summary

### `com.bun.platform.catalog.offer.domain`

Provides the core offer entity and domain-level pricing helpers.

Main concerns:

- `Offer` lifecycle state
- `OfferType`
- `OfferStatus`
- discount calculation
- variant-offer projection used for reassignment

### `com.bun.platform.catalog.offer.service`

Provides command handling, lifecycle management, reassignment, and batch processing.

Main concerns:

- command entry points
- ownership validation
- optimistic retry for write contention
- reassignment of effective offers to variants
- scheduled lifecycle transitions

## Type Reference

### `Offer`

**Kind:** aggregate root entity  
**Package:** `com.bun.platform.catalog.offer.domain`

#### Description

Represents a direct price reduction applied to catalog variants.

The current implementation is explicitly variant-oriented. A product-level offer is implemented by linking the offer to the variants belonging to that product.

#### Responsibilities

- store offer metadata and lifecycle dates
- track seller ownership
- maintain linked target variants
- expose lifecycle state at an instant in time
- enforce core invariants for date range and discount value

#### Key Fields

- `id`
- `name`
- `description`
- `offerType`
- `discountValue`
- `startDate`
- `endDate`
- `isStopped`
- `isLifecycleApplied`
- `sellerId`
- `variants`
- `createdAt`
- `updatedAt`
- `version`

#### Persistence Notes

- mapped to `offers`
- soft delete enabled
- many-to-many relation to `Variant` through `offer_variants`
- optimistic locking through `version`

#### Public Behavioral Contract

- `statusAt(Instant)` returns one of `DRAFT`, `ACTIVE`, `SUSPENDED`, or `EXPIRED`
- `suspend()` moves the offer into a stopped state unless it is already stopped
- `resume(Instant)` clears the stopped state unless the offer is expired
- `canActivate(Instant)` and `canResume(Instant)` reject expired offers
- `markLifecycleApplied()` indicates that active lifecycle changes have been materialized
- `markLifecycleDeactivated()` clears that lifecycle-applied flag

#### Invariants

- discount value must be greater than `0` and less than or equal to `100`
- `startDate` must be before or equal to `endDate`

### `OfferType`

**Kind:** enum  
**Package:** `com.bun.platform.catalog.offer.domain`

#### Description

Defines supported discount semantics.

#### Current Values

- `PERCENTAGE`

#### Notes

- only percentage-based discounts are supported in the current model

### `OfferStatus`

**Kind:** enum  
**Package:** `com.bun.platform.catalog.offer.domain`

#### Values

- `DRAFT`
- `ACTIVE`
- `SUSPENDED`
- `EXPIRED`

### `OfferCalculator`

**Kind:** domain utility  
**Package:** `com.bun.platform.catalog.offer.domain`

#### Description

Calculates the discount amount for an offer based on base price and discount configuration.

#### Main Operation

- `calculateDiscountAmount(OfferType, BigDecimal, BigDecimal)`

#### Behavioral Contract

- current implementation only calculates percentage discounts
- result is rounded using `HALF_UP` to 2 decimal places

### `OfferVariantProj`

**Kind:** projection record  
**Package:** `com.bun.platform.catalog.offer.domain`

#### Description

Lightweight projection used during reassignment to evaluate all currently active offers affecting a variant.

#### Main Fields

- `variantId`
- `offerId`
- `offerType`
- `discountValue`
- `startDate`
- `endDate`
- `isStopped`

## Service Reference

### `OfferCommandService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.offer.service`

#### Description

Acts as the command entry point for offer creation, targeting changes, and lifecycle commands.

#### Main Operations

- `createOffer(Long, OfferCreateRequestDto)`
- `addVariants(Long, Long, Set<Long>)`
- `removeVariants(Long, Long, Set<Long>)`
- `addProducts(Long, Long, Set<Long>)`
- `removeProducts(Long, Long, Set<Long>)`
- `stopOffer(Long, Long)`
- `resumeOffer(Long, Long)`
- `activateOfferNow(Long, Long)`

#### Behavioral Guarantees

- seller-scoped commands require seller ownership
- write operations use optimistic retry for lock conflicts
- impacted product caches are evicted after offer-target changes
- reassignment is triggered after operations that can affect effective pricing

#### Create Offer Contract

The `createOffer(Long, OfferCreateRequestDto)` method:

1. constructs an `Offer` from request data
2. sets seller ownership
3. defaults `isStopped` to `false`
4. persists the entity through `OfferRepository.save`

Strict failures:

- invalid discount value
- invalid date range
- invalid request payload at DTO validation level

### `OfferManagementFacade`

**Kind:** application facade  
**Package:** `com.bun.platform.catalog.offer.service`

#### Description

Owns transactional lifecycle and association updates using `REQUIRES_NEW` boundaries.

#### Main Operations

- `linkVariantsToOffer(Long, Long, Set<Long>)`
- `detachVariantsFromOffer(Long, Long, Set<Long>)`
- `stopOffer(Long, Long)`
- `startOfferNow(Long, Long)`
- `resumeOffer(Long, Long)`
- `batchActivateOffersNow()`
- `batchDeactivateOffersNow()`

#### Behavioral Guarantees

- offer must exist and belong to the seller
- all target variants must belong to the same seller
- detaching and stopping clear active offer references from variants inside the transactional workflow
- batch lifecycle methods toggle `isLifecycleApplied`

### `OfferReassignmentService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.offer.service`

#### Description

Coordinates reassignment of the best available active offer onto variants.

#### Main Operations

- `deactivateAndReassignOffers()`
- `activateAndReassignOffers()`
- `reassignOfferToVariantBatch(Set<Long>)`
- `findActiveVariantsOffersMap(Set<Long>)`
- `applyDiscountByOfferId(Long, BigDecimal)`

#### Behavioral Guarantees

- processes variant IDs in batches of `50`
- queries only currently active and non-stopped offers for reassignment
- delegates the final write to `OfferReassignmentFacade`

### `OfferReassignmentFacade`

**Kind:** application facade  
**Package:** `com.bun.platform.catalog.offer.service`

#### Description

Applies or clears materialized offer data on variants.

#### Main Operations

- `reassignOfferToVariantBatchHelper(List<Variant>, Map<Long, List<OfferVariantProj>>)`

#### Behavioral Guarantees

- chooses the offer with the largest discount amount
- breaks ties by later `endDate`
- clears offer state when no active offer remains
- writes effective state onto `VariantPrice`:
  - `discountAmount`
  - `activeOfferId`
  - `offerEndsAt`
  - `offerType`

### `OfferScheduler`

**Kind:** scheduled component  
**Package:** `com.bun.platform.catalog.offer.job`

#### Description

Runs periodic activation and deactivation workflows for offer lifecycle application.

#### Scheduled Operations

- activation job: every 5 minutes
- deactivation job: every 4 minutes

#### Behavioral Guarantees

- activation triggers lifecycle-application update then reassignment
- deactivation removes applied offer state then reassigns remaining active offers

## REST API Reference

### Offer Management API

**Controller:** `OfferController`  
**Base path:** `/api/admin/offers`

#### Endpoints

- `POST /`
- `POST /{offerId}/variants`
- `DELETE /{offerId}/variants`
- `POST /{offerId}/products`
- `DELETE /{offerId}/products`
- `POST /{offerId}/stop`
- `POST /{offerId}/resume`
- `POST /{offerId}/activate`

#### Observations

- the current controller accepts `sellerId` as a method parameter rather than resolving it from a security principal
- the path prefix is `/api/admin/offers`, while service-level authorization uses seller semantics

## DTO Reference

### `OfferCreateRequestDto`

#### Purpose

Write model for creating an offer.

#### Fields

- `name`
- `description`
- `offerType`
- `discountValue`
- `startDate`
- `endDate`

#### Validation Summary

- `name` required
- `offerType` required
- `discountValue` required and positive
- `startDate` required
- `endDate` required

### `OfferResponseDto`

#### Purpose

Response model representing an offer with linked products and variants.

#### Fields

- `id`
- `name`
- `description`
- `offerType`
- `discountValue`
- `startDate`
- `endDate`
- `enabled`
- `isStopped`
- `productIds`
- `variantIds`

## Persistence Reference

### Primary Tables

- `offers`
- `offer_variants`

### Related Product Tables

- `variants`

### Structural Constraints

- `offer_variants` uses composite primary key `(offer_id, variant_id)`
- variants reference the currently applied offer through `active_offer_id`
- variant price state also stores `offer_type` and `offer_ends_at`

## Domain Invariants

- offer discount must remain within `(0, 100]`
- start date must not be after end date
- expired offers cannot be resumed or activated
- stopped offers must not remain materially applied as active variant pricing
- effective offer state is materialized on `VariantPrice`, making variant pricing the runtime source of truth

## Lifecycle Model

### Offer States

- `DRAFT`: current time is before `startDate`
- `ACTIVE`: current time is within range and `isStopped = false`
- `SUSPENDED`: manually stopped
- `EXPIRED`: current time is after `endDate`

### Lifecycle Application Model

The domain distinguishes between:

- logical status derived from dates and `isStopped`
- materialized pricing state written onto variants

The `isLifecycleApplied` flag tracks whether the lifecycle state has already been pushed into the variant pricing layer.

## Targeting Rules

### Variant Targeting

- offer-to-variant links are stored directly in `offer_variants`
- variant ownership is validated against seller ownership before linking

### Product Targeting

- product-level operations are converted to variant-level operations
- `OfferCommandService.addProducts(...)` and `removeProducts(...)` resolve seller-owned variant IDs first

## Reassignment Rules

Observed in `OfferReassignmentFacade`:

- all currently active offers for a variant are considered
- the offer with the highest calculated discount is selected
- if two offers give the same discount, the one with the later `endDate` wins
- if no valid offer remains, the variant offer fields are cleared

## Domain Events

Offer mutations now emit typed domain events from `com.bun.platform.catalog.offer.event`.

Primary events:

- `OfferCreatedEvent`
- `OfferVariantsLinkedEvent`
- `OfferVariantsUnlinkedEvent`
- `OfferStoppedEvent`
- `OfferResumedEvent`
- `OfferActivatedEvent`
- `OfferBatchActivatedEvent`
- `OfferBatchDeactivatedEvent`

Publication notes:

- `OfferCommandService.createOffer(...)` publishes `OfferCreatedEvent`
- `OfferManagementFacade` publishes targeting and lifecycle events inside its `REQUIRES_NEW` mutation boundaries
- `OfferEventListener` handles those events after commit through `@TransactionalEventListener`

## Exception Handling

### English

- Offer operations should return bilingual error payloads with clear business classification so seller tools can distinguish validation, ownership, lifecycle, and concurrency failures.
- `400 Bad Request`: use for invalid discount values, invalid date windows, malformed target lists, or unsupported or incorrect offer input.
- `404 Not Found`: use when the target offer, product, or variant does not exist within the seller's accessible scope.
- `409 Conflict`: use for attempts to stop an already stopped offer, activate or resume an expired offer, or save during optimistic-lock contention or reassignment conflicts.
- `403 Forbidden`: use when a seller attempts to manage another seller's offers or variants.
- `500 Internal Server Error`: reserve for scheduler failures, reassignment or caching synchronization failures, or other unexpected runtime errors.
- Current implementation note: several offer-management paths still throw raw `RuntimeException`; those paths should be normalized to explicit `404` or `409` responses with stable error codes.

### العربية

- يجب أن تعيد عمليات العروض حمولة أخطاء ثنائية اللغة مع تصنيف أعمال واضح حتى تستطيع أدوات البائع التمييز بين أخطاء التحقق والملكية والحالة والتزامن.
- `400 طلب غير صحيح`: يستخدم عند وجود قيمة خصم غير صالحة، أو نطاق زمني غير صحيح، أو قوائم استهداف مشوهة، أو مدخلات عرض غير مدعومة أو غير صحيحة.
- `404 غير موجود`: يستخدم عندما لا يكون العرض أو المنتج أو المتغير المستهدف موجوداً ضمن نطاق البائع المصرح له.
- `409 تعارض`: يستخدم عند محاولة إيقاف عرض موقوف بالفعل، أو تفعيل أو استئناف عرض منتهي، أو الحفظ أثناء تعارض قفل تفاؤلي أو تعارض إعادة تعيين للعروض.
- `403 ممنوع`: يستخدم عندما يحاول بائع إدارة عروض أو متغيرات تخص بائعاً آخر.
- `500 خطأ داخلي في الخادم`: يحجز لأعطال المجدول، أو فشل مزامنة إعادة التعيين والكاش، أو أي خطأ تشغيلي غير متوقع.
- ملاحظة تنفيذية حالية: بعض مسارات إدارة العروض ما زالت ترمي `RuntimeException` مباشرة، ويجب تحويلها إلى استجابات صريحة من نوع `404` أو `409` مع رموز أخطاء ثابتة.

## Cache and Side Effects

- impacted product caches are evicted after link, unlink, stop, resume, activate, and scheduled lifecycle changes
- reassignment updates the effective variant pricing state
- stopping or batch deactivation removes active offer references from variants before reassignment

## Security Notes

- `OfferCommandService.createOffer(...)` is annotated with `@PreAuthorize("hasRole('SELLER')")`
- ownership checks are enforced by `findByIdAndSellerId(...)` and seller-scoped variant counting
- the controller layer currently does not yet reflect the same security model cleanly

## Implementation Notes

- the domain is variant-first even when the API exposes product-level helper operations
- applied pricing lives on `VariantPrice`, not on `Offer`
- lifecycle application is decoupled from raw date evaluation through `isLifecycleApplied`
- optimistic retry is used for mutation flows that may race on offer version updates
