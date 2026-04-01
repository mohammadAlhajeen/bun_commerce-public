# Product Domain Reference

## Overview

The `Product` domain defines the sellable catalog model used by the platform storefront and seller back office.

It is responsible for:

- product definition lifecycle
- variant-based pricing and availability
- tracked inventory reservation for tracked variants
- product configuration attributes
- product media references
- tag assignment
- public and seller-facing product reads
- collection curation and ordering
- catalog event publication

Primary package:

- `com.bun.platform.catalog.product`

Collaborating packages:

- `com.bun.platform.catalog.category`
- `com.bun.platform.catalog.offer`

## Package Summary

### `com.bun.platform.catalog.product`

Provides the core catalog aggregate and its write/read orchestration.

Main concerns:

- `ProductDefinition` aggregate root
- `Variant` lifecycle
- tracked inventory state for `InventoryPolicy.TRACKED`
- attribute and media composition
- collection management
- public product-card and detail reads
- cache-aware storefront access

## Type Reference

### `ProductDefinition`

**Kind:** aggregate root entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents a seller-owned product definition visible in the catalog.

#### Responsibilities

- hold public product metadata
- bind the product to a sellable category
- own all product variants
- maintain tags and collection memberships
- expose activation state and summary metrics

#### Key Fields

- `id`
- `name`
- `description`
- `currency`
- `fulfillmentTime`
- `isActive`
- `averageRating`
- `salesCount`
- `version`
- `sellerId`
- `category`
- `variants`
- `productCollectionItems`
- `tags`
- `inventoryPolicy`
- `mainImageId`
- `createdAt`
- `updatedAt`

#### Persistence Notes

- mapped to `product_definitions`
- soft delete enabled
- optimistic locking through `version`
- seller relation stored as scalar `sellerId`

### `Variant`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents a concrete purchasable variant of a product.

#### Responsibilities

- store purchasable price state
- control default variant selection
- control active/inactive variant availability
- constrain order quantity
- own attribute and media instances

#### Key Fields

- `id`
- `name`
- `productDefinition`
- `price`
- `sku`
- `isActive`
- `salesCount`
- `maxOrderQuantity`
- `attributes`
- `medias`
- `isDefault`
- `createdAt`
- `updatedAt`
- `version`

#### Public Behavioral Contract

- `setActive(false)` clears the default flag
- `setDefault(true)` ensures the variant is active
- `validateOrderQuantity(int)` rejects zero, negative, and excessive quantities

#### Persistence Notes

- mapped to `variants`
- soft delete enabled
- partial unique index enforces one default variant per product at database level

### `Inventory`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents tracked stock for one variant.

This model is intentionally minimal:

- `qtyOnHand` = total stock owned by the merchant
- `qtyReserved` = stock temporarily reserved
- `available` = computed at runtime as `qtyOnHand - qtyReserved`

#### Responsibilities

- hold tracked stock for one variant
- expose computed available quantity without persisting it
- protect stock from going negative
- prevent reserved quantity from exceeding on-hand quantity
- update `updatedAt` whenever stock changes

#### Key Fields

- `variantId`
- `qtyOnHand`
- `qtyReserved`
- `updatedAt`

#### Public Behavioral Contract

- `getAvailable()` returns `qtyOnHand - qtyReserved`
- `reserve(int)` rejects zero, negative, and over-available requests
- `release(int)` rejects zero, negative, and over-release requests
- `commit(int)` reduces both reserved and on-hand stock

#### Persistence Notes

- mapped to `inventories`
- primary key is `variantId`
- availability is computed and not stored in the database
- database constraints enforce:
  - `qty_on_hand >= 0`
  - `qty_reserved >= 0`
  - `qty_reserved <= qty_on_hand`

### `VariantPrice`

**Kind:** embeddable value object  
**Package:** `com.bun.platform.catalog.product`

#### Description

Stores price and active-offer state for a variant.

#### Known Fields

- `basePrice`
- `discountAmount`
- `activeOfferId`
- `offerType`
- `offerEndsAt`

### `VariantAttribute`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents an attribute instance attached to a specific variant.

#### Responsibilities

- carry variant-specific attribute metadata
- reference shared attribute definition by ID
- distinguish required and optional inputs
- own available selections

#### Key Fields

- `id`
- `name`
- `attributeId`
- `isRequired`
- `isActive`
- `optionType`
- `selections`
- `variant`

### `VariantAttributeSelection`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents one selectable value inside a variant attribute.

#### Responsibilities

- carry selection display data
- support default and active markers
- reference optional media and attribute-value definitions
- preserve display sort order

### `VariantMedia`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents a media reference owned by a variant.

#### Key Fields

- `id`
- `mediaItemId`
- `variant`
- `mainMedia`
- `sortOrder`

### `Tag`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents a reusable product label shared across many products.

#### Behavioral Contract

- names are normalized to lowercase and trimmed on persist/update

### `ProductCollection`

**Kind:** aggregate root entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents a seller-curated collection used for storefront presentation.

#### Responsibilities

- expose collection metadata and public slug
- own ordered membership entries
- control active/inactive storefront visibility

#### Key Fields

- `id`
- `name`
- `slug`
- `description`
- `sellerId`
- `isActive`
- `deleted`
- `mediaItemId`
- `collectionItems`
- `createdAt`
- `updatedAt`
- `version`

#### Persistence Notes

- mapped to `product_collections`
- deletion implemented through custom SQL soft delete

### `ProductCollectionItem`

**Kind:** entity  
**Package:** `com.bun.platform.catalog.product`

#### Description

Represents membership of one product inside one collection with an explicit ordering value.

#### Responsibilities

- link one collection to one product
- preserve storefront order
- prevent duplicate membership

#### Key Fields

- `id`
- `collection`
- `productDefinition`
- `sortOrder`
- `createdAt`
- `updatedAt`

## Service Reference

### `ProductService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Owns write-side product lifecycle operations.

#### Main Operations

- `createProduct(Long, CreateProductDefinitionDTO)`
- `updateProductBasicInfo(Long, Long, String, String, UUID, List<String>)`
- `updateProductPrice(Long, Long, BigDecimal)`
- `setProductActive(Long, Long, boolean)`
- `deleteProduct(Long, Long)`
- `deleteProduct(Long)`

#### Behavioral Guarantees

- rejects product creation without variants
- rejects assignment to non-sellable categories
- creates initial variants before final product persistence
- initializes per-variant inventory rows when `inventoryPolicy == TRACKED`
- ensures one default variant exists after creation
- resolves product main image from validated media or default variant media
- publishes product lifecycle events

#### Create Product Contract

The `createProduct(Long, CreateProductDefinitionDTO)` method is the authoritative write path behind `POST /api/seller/products`.

Execution steps:

1. validate that at least one variant request exists
2. load the category using `CategoryService.findById`
3. reject the request if the category is not sellable
4. construct the base `ProductDefinition`
5. normalize and attach tags through `TagService.processAndFetchTags`
6. create variant objects through `createVeriants(...)`
7. ensure that one default variant exists
8. resolve the product main image:
   - first try `dto.mainImageId` through `CatalogeMediaService.fetchValidMediaIdForSeller`
   - otherwise fallback to the default variant main media
   - if neither is available, leave `mainImageId` null
9. persist the aggregate through `ProductRepository.save`
10. when `inventoryPolicy == TRACKED`, create initial `Inventory` rows for the saved variants
11. publish `ProductCreatedEvent`

Strict failures in this method:

- missing variants
- missing category
- non-sellable category
- no default variant after internal variant assembly

### `VariantService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Builds variants and exposes helper queries needed by other bounded contexts.

#### Main Operations

- `createVariant(CreateVariantDTO, ProductDefinition, Long)`
- `updateVariantBasic(Long, Long, String)`
- `getVariantByIdAndSellerId(Long, Long)`
- `getCartProjectionOrNull(Long)`
- offer and bulk-lookup helper methods

#### Behavioral Guarantees

- attaches media through `CatalogeMediaService`
- attaches attributes through `VariantAttributeService`
- returns cart-friendly projections for downstream cart logic

#### Create Variant Contract

The `createVariant(CreateVariantDTO, ProductDefinition, Long)` method performs variant assembly during product creation.

Execution steps:

1. create the `Variant` object
2. assign product reference, name, active flag, and `VariantPrice`
3. set `maxOrderQuantity`
4. attach media through `CatalogeMediaService.handleMediaItems`
5. attach attributes through `VariantAttributeService.createVariantAttributes`

Observed tolerance behavior:

- invalid or missing media references are ignored
- empty media input results in an empty media list
- attribute creation may ignore invalid attribute-value references and continue

### `ProductVariantService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Owns variant lifecycle operations inside an existing product aggregate.

#### Main Operations

- `addVariant(Long, Long, CreateVariantDTO)`
- `addTrackedVariant(Long, CreateTrackedVariantDTO)`
- `removeVariant(Long, Long, Long)`
- `changeDefaultVariant(Long, Long, Long)`
- `activateVariant(Long, Long, Long)`
- `deactivateVariant(Long, Long, Long)`
- `updateVariantPrice(Long, Long, Long, BigDecimal)`
- `updateDefaultVariantPrice(Long, BigDecimal)`

#### Behavioral Guarantees

- prevents more than five variants per product
- prevents loss of the last active variant
- prevents inactive variants from remaining default
- creates initial tracked inventory when adding a tracked variant
- reassigns default variant when required
- recalculates discount state when active offers exist
- publishes variant lifecycle and price-change events

### `InventoryService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Owns the simple tracked-inventory model used by `InventoryPolicy.TRACKED`.

#### Main Operations

- `getAvailableQuantities(List<Long>)`
- `createInitialInventory(Long, int)`
- `assertAvailable(Long, int)`
- `reserveTrackedStock(Long, int)`
- `releaseTrackedStock(Long, int)`
- `commitTrackedStock(Long, int)`
- `consumeTrackedStock(Map<Long, Integer>)`
- `consumeTrackedStock(Long, int)`
- `applyInventoryPolicyToOrderItem(Order, OrderItem, InventoryPolicy, Long, int)`

#### Behavioral Guarantees

- returns computed available stock, not persisted availability
- creates one inventory row per tracked variant
- rejects negative initial stock
- rejects non-positive reservation and consumption quantities
- validates tracked availability using `qtyOnHand - qtyReserved`
- orchestrates stock mutations without embedding SQL or locking logic
- delegates atomic reserve, release, and commit updates to `InventoryRepository`
- translates zero-row repository results into inventory-specific conflicts

### `InventoryRepository`

**Kind:** infrastructure repository  
**Package:** `com.bun.platform.catalog.product.repository`

#### Description

Owns atomic persistence operations for tracked inventory.

#### Main Operations

- `findByVariantIdIn(List<Long>)`
- `reserve(Long, int, Instant)`
- `release(Long, int, Instant)`
- `commit(Long, int, Instant)`

#### Behavioral Guarantees

- each stock mutation is executed as a single conditional database update
- reservation succeeds only when the requested quantity fits inside current availability
- release and commit succeed only when enough stock is already reserved
- `updatedAt` is written by the same atomic update statement

### `ProductReadService`

**Kind:** query service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Builds full product DTOs and lightweight product-card reads.

#### Main Operations

- `getProductForSeller(Long, Long)`
- `getProductForAdmin(Long)`
- `getActiveProduct(Long)`
- `getProductCard(Long)`

#### Behavioral Guarantees

- seller/admin reads include inactive paths
- public reads only expose active product and active variants
- product-card reads are cacheable
- seller/admin reads publish `ProductViewedEvent`

### `ProductViewService`

**Kind:** query facade  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Public-facing facade that wraps active product reads and emits view events with viewer type semantics.

### `CollectionService`

**Kind:** application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Owns collection lifecycle, membership, ordering, and public storefront retrieval.

#### Main Operations

- collection create/read/update/delete methods
- `addProductToCollection(...)`
- `removeProductFromCollection(...)`
- `reorderCollectionItems(...)`
- `getCollectionProductCards(Long, int, int)`

#### Behavioral Guarantees

- collection slug must be unique per seller
- duplicate membership is rejected
- membership changes trigger collection-cache eviction
- public collection reads exclude inactive collections

### `ProductCacheService`

**Kind:** infrastructure-facing application service  
**Package:** `com.bun.platform.catalog.product.service`

#### Description

Provides two-level cache support for storefront product-card retrieval.

#### Cache Contract

- level 1: `product_card`
- level 2: `product_card_collections`

#### Behavioral Guarantees

- product-card cache entries are evicted for impacted products
- collection cache entries are evicted after collection membership and collection metadata changes

## REST API Reference

### Seller Product Management

**Controller:** `SellerProductController`  
**Base path:** `/api/seller/products`

#### Product Operations

- `POST /`
- `GET /{id}`
- `PUT /{id}/basic-info`
- `PATCH /{id}/price`
- `PATCH /{id}/activate`
- `DELETE /{id}`

#### Variant Operations

- `POST /{productId}/variants`
- `DELETE /{productId}/variants/{variantId}`
- `PATCH /{productId}/variants/{variantId}/set-default`
- `PATCH /{productId}/variants/{variantId}/activate`
- `PATCH /{productId}/variants/{variantId}/deactivate`
- `PATCH /{productId}/variants/{variantId}/price`

#### Tracked Variant Operations

**Controller:** `SellerVariantController`  
**Base path:** `/api/variants`

- `POST /tracked`

#### Authentication Model

- seller identity resolved from JWT through `UserIdentityService`

#### Create Product Endpoint Behavior

The controller documentation defines product creation as a tolerant draft operation.

Stated controller-level guarantees:

- creation prioritizes progress over strict rejection of optional-input issues
- non-critical issues may be sanitized, normalized, or ignored
- critical domain violations still fail the request

Documented tolerance scope:

- missing or invalid media references
- invalid attribute values
- multiple default selections
- optional field inconsistencies

Documented strictness boundary:

- tolerant behavior applies only to product creation
- other domains such as orders and payments remain strict

### Public Product API

**Controller:** `PublicProductController`  
**Base path:** `/api/public/products`

#### Endpoints

- `GET /{id}`
- `GET /card/{id}`

### Public Collection API

**Controller:** `PublicCollectionController`  
**Base path:** `/api/public/collections`

#### Endpoints

- `GET /{id}/products`
- `GET /slug/{slug}/products`
- `GET /{id}`
- `GET /slug/{slug}`

## DTO Reference

### `CreateProductDefinitionDTO`

#### Purpose

Write model for initial product creation.

#### Key Fields

- `name`
- `description`
- `fulfillmentMinDays`
- `fulfillmentMaxDays`
- `inventoryPolicy`
- `isActive`
- `categoryId`
- `variantsDto`
- `tags`
- `mainImageId`

#### Validation Summary

- product name length `3..255`
- category ID required
- variant count `1..5`
- tag count up to `5`

#### Runtime Interpretation During Product Creation

- `isActive` defaults to `true` when omitted
- `mainImageId` is optional and may be ignored if it does not belong to the seller
- `tags` are normalized, deduplicated, and persisted through an upsert workflow

### `CreateVariantDTO`

#### Purpose

Write model for variant creation.

#### Key Fields

- `name`
- `isActive`
- `isDefault`
- `basePrice`
- `maxOrderQuantity`
- `attributesDto`
- `variantMediasDto`

#### Validation Summary

- `basePrice` required
- up to `10` attributes
- up to `5` media items

#### Runtime Interpretation During Product Creation

- `isActive` defaults to `true` when omitted
- `isDefault` is honored only for the first active variant marked as default
- if no default variant survives assembly, the first variant becomes default

### `CreateTrackedVariantDTO`

#### Purpose

Write model for creating one tracked variant through the dedicated tracked-variant endpoint.

#### Key Fields

- `productId`
- `name`
- `basePrice`
- `initialStock`
- `maxOrderQuantity`
- `isActive`
- `isDefault`
- `attributes`

#### Validation Summary

- product ID required
- variant name required
- base price required
- initial stock must be `>= 0`
- max order quantity must be `>= 1`
- up to `10` tracked attributes

#### Runtime Interpretation

- only valid for products with `InventoryPolicy.TRACKED`
- creates a variant and then initializes its inventory row
- tracked attributes must be unique and must resolve to category-valid definitions and selections

### `TrackedAttributeDTO`

#### Purpose

Minimal tracked-variant attribute input that binds one attribute to one selected value.

#### Key Fields

- `attributeId`
- `selectionId`

## Persistence Reference

### Primary Tables

- `product_definitions`
- `variants`
- `inventories`
- `variant_attributes`
- `variant_attribute_selection`
- `variant_medias`
- `tags`
- `product_tags`
- `product_collections`
- `product_collection_items`

### Supporting Tables

- `categories`
- `attribute_definitions`
- `attribute_values`
- `category_attributes`
- `offers`
- `offer_collections`

### Structural Constraints

- one default variant per product enforced by partial unique index
- one inventory row per tracked variant through `variant_id` primary key
- `qty_on_hand >= 0`
- `qty_reserved >= 0`
- `qty_reserved <= qty_on_hand`
- unique tag name
- unique `(collection_id, product_id)` membership
- seller/activity indexes on products and collections

## Domain Invariants

- a product must contain at least one variant
- a product may only be assigned to a sellable category
- the default variant must be active
- at least one active variant must remain after variant lifecycle changes
- a product may contain at most five variants in the current implementation
- tracked inventory availability is always computed as `qtyOnHand - qtyReserved`
- tracked inventory never allows negative on-hand or reserved stock
- tracked inventory never allows reserved stock to exceed on-hand stock
- public reads return only active catalog state
- collection membership is unique per product and collection pair

## Create Product Processing Rules

### Controller-Level Rules

- endpoint requires authenticated seller context
- endpoint is explicitly documented as tolerant draft creation
- optional invalid input may be ignored instead of failing the request

### ProductService Rules

- category existence is mandatory
- category sellability is mandatory
- product persistence happens only after variant assembly completes
- one default variant must exist before save

### Tag Processing Rules

Observed in `TagService.processAndFetchTags(...)`:

- null tags are removed
- tags are trimmed
- tags are lowercased
- duplicate tags are removed
- tags are upserted before loading final `Tag` entities

### Media Processing Rules

Observed in `CatalogeMediaService.handleMediaItems(...)`:

- null and duplicate media DTOs are removed
- media must belong to the seller to be accepted
- invalid seller/media combinations are ignored
- only the first declared main media is retained
- when no main media is declared, the first accepted media becomes main

### Attribute Processing Rules

Observed in `VariantAttributeService`:

- category-bound global attribute definitions take precedence over frontend option type
- if the frontend sends a conflicting option type for a global attribute, the global definition wins
- invalid `attributeValueId` references are tolerated and treated as local values
- for `FIXED` and `FREE_INPUT` attributes, extra selections are ignored
- if multiple default selections are submitted, only the first active default is retained
- for optional attributes with no declared default, the first selection becomes default

### Inventory Processing Rules

Observed in `Inventory`, `InventoryService`, and `InventoryRepository`:

- tracked variants receive an `Inventory` row with `qtyOnHand = initialStock` and `qtyReserved = 0`
- available stock is computed dynamically as `qtyOnHand - qtyReserved`
- the `Inventory` entity defines the business rules and invariants only
- the `InventoryService` coordinates the use case and interprets repository outcomes
- the `InventoryRepository` performs concurrency-safe reserve, release, and commit updates with conditional SQL
- `reserve(qty)` increases only `qtyReserved`
- `release(qty)` decreases only `qtyReserved`
- `commit(qty)` decreases both `qtyReserved` and `qtyOnHand`
- no inventory expiration, cart-hold, Redis, or event-sourcing logic exists in this model

## Exception Handling

### English

- Product errors should be returned through the bilingual platform error contract and should never expose stack traces or persistence internals to storefront clients.
- `400 Bad Request`: use for malformed product payloads, products without variants, prices less than or equal to zero, inactive default variants, more than five variants, or invalid media or attribute selections.
- `404 Not Found`: use when required references such as category, product, variant, collection, or tag do not exist in the requested scope.
- `409 Conflict`: use for duplicate collection membership, lifecycle-state conflicts, default-variant conflicts, or optimistic-write contention during concurrent catalog updates.
- `403 Forbidden`: use when seller or admin ownership checks fail and the caller is not allowed to mutate the target catalog resource.
- `500 Internal Server Error`: reserve for media lookup or storage failures, event-publication failures, or any unexpected catalog runtime failure.
- Current implementation note: most product flows still classify failures through `IllegalArgumentException`; professional handling should progressively replace message-based decisions with explicit product-specific exception types and error codes.

### العربية

- يجب أن تعاد أخطاء نطاق المنتجات من خلال عقد الأخطاء ثنائي اللغة في المنصة، مع عدم كشف التتبعات الداخلية أو تفاصيل التخزين لعملاء المتجر.
- `400 طلب غير صحيح`: يستخدم عند وجود حمولة منتج غير صالحة، أو منتج بلا متغيرات، أو سعر أقل من أو يساوي الصفر، أو متغير افتراضي غير نشط، أو أكثر من خمسة متغيرات، أو اختيارات وسائط أو سمات غير صحيحة.
- `404 غير موجود`: يستخدم عندما تكون المراجع المطلوبة مثل التصنيف أو المنتج أو المتغير أو المجموعة أو الوسم غير موجودة ضمن النطاق المطلوب.
- `409 تعارض`: يستخدم عند وجود عضوية مكررة داخل مجموعة، أو تعارض في حالة دورة الحياة، أو تعارض في تحديد المتغير الافتراضي، أو تزاحم تحديثات متزامنة على الكتالوج.
- `403 ممنوع`: يستخدم عندما تفشل فحوصات الملكية الخاصة بالبائع أو المدير ولا يكون للمستدعي حق تعديل المورد المطلوب.
- `500 خطأ داخلي في الخادم`: يحجز لفشل البحث عن الوسائط أو تخزينها، أو فشل نشر الأحداث، أو أي خطأ غير متوقع داخل تشغيل الكتالوج.
- ملاحظة تنفيذية حالية: معظم مسارات المنتجات ما زالت تصنف الإخفاقات عبر `IllegalArgumentException`، والمعالجة الاحترافية تتطلب استبدال هذا النمط تدريجياً باستثناءات ورموز أخطاء مخصصة للمنتجات.

## Domain Events

Published event types observed in the implementation:

- `ProductCreatedEvent`
- `ProductActivatedEvent`
- `ProductDeactivatedEvent`
- `ProductDeleteEvent`
- `VariantCreatedEvent`
- `VariantActivatedEvent`
- `VariantDeactivatedEvent`
- `VariantPriceChangedEvent`
- `DefaultVariantChangedEvent`
- `ProductViewedEvent`

## Security Notes

- seller write operations require `ROLE_SELLER`
- some service methods provide admin-only variants
- public product and collection reads are unauthenticated
- ownership checks compare the stored `sellerId` against the authenticated seller

## Implementation Notes

- `ProductDefinition` still declares joined inheritance even though the current runtime model behaves as a concrete aggregate root
- product creation intentionally tolerates some optional-input issues for draft-style workflows
- public reads are split between `ProductViewService` and `ProductReadService`
- collection rendering uses explicit two-level caching to avoid repeated full product queries
- tolerant creation is mostly realized by downstream sanitization in tag, media, and attribute services, while category and variant-presence checks remain strict
