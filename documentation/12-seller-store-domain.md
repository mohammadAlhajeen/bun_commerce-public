# Seller Store Domain

## Overview

The `Seller Store` module provides the public seller storefront read model for the marketplace.

It exists to answer one specific use case efficiently:

- resolve a seller store by slug
- return lightweight store profile data
- return paginated product cards
- support category, price-range, and keyword filtering
- keep reads cache-friendly and join-light

Related diagrams: `documentation/12-seller-store-uml.md`

Primary package:

- `com.bun.platform.sellerstore`

Supporting packages:

- `com.bun.platform.store`
- `com.bun.platform.catalog.product`
- `com.bun.platform.catalog.category`
- `com.bun.platform.config`

## 1. Architectural Interpretation

### Core interpretation

This is not a new write-heavy seller aggregate.

It is a read-optimized storefront projection layer that composes:

- store profile state from `stores`
- product summary state from `product_definitions`
- price state from the default `variants` row
- cache invalidation from product/store events

### What the module is responsible for

- public store page retrieval by slug
- store-scoped product listing
- store-scoped filters and pagination
- projection-only store card shaping
- cache key generation and cache invalidation

### What the module is not responsible for

- product writes
- offer application logic
- price mutation
- inventory reservation
- seller back-office page editing

### Public URL vs API URL

The public store is conceptually addressed by:

- `/store/{slug}`

The backend read API exposed by the current implementation is:

- `GET /api/stores/{slug}`

That means the frontend route `/store/{slug}` should consume the API route rather than forcing the backend to serve HTML directly.

## 2. Domain Boundary Rules

### Product price source of truth

The module fully respects the existing product-domain rule:

- product does not own price
- variant is the single source of truth
- the default variant is the only storefront price source

The store module never mutates price state and never introduces a parallel store-level price model.

### Why inline effective-price computation is still valid

The requirement says the store domain must not calculate price.

In this implementation:

- the application service does not calculate price
- the domain model does not calculate price
- the repository query projects effective price directly from persisted default-variant fields

So the module is not becoming a pricing domain. It is only reading already-owned pricing state through a projection expression.

### Upstream ownership

The store profile persistence is still physically backed by the legacy `com.bun.platform.store.Store` entity.

The seller-store module treats it as an upstream persistence source and adds its own read-facing domain records and DTOs on top.

## 3. Package Structure

### `com.bun.platform.sellerstore.domain`

Purpose:

- small immutable domain records and value objects used by the read model

Current types:

- `SellerStore`
- `StoreSlug`
- `StoreTheme`

### `com.bun.platform.sellerstore.application`

Purpose:

- public store-page orchestration
- cache key creation
- cache invalidation behavior

Current types:

- `SellerStorePageService`
- `StorePageCacheKeyFactory`
- `StorePageCacheInvalidationService`

### `com.bun.platform.sellerstore.application.dto`

Purpose:

- transport-oriented API response and filter models

Current types:

- `StorePageFilter`
- `StoreSummaryDto`
- `StoreProductCardDto`
- `StoreAvailableFiltersDto`
- `StoreCategoryFilterDto`
- `StoreAppliedFiltersDto`
- `StorePaginationDto`
- `StorePageResponse`

### `com.bun.platform.sellerstore.infrastructure.persistence`

Purpose:

- projection repository for optimized native queries

Current types:

- `StorePageReadRepository`
- projection interfaces under `projection/`

### `com.bun.platform.sellerstore.infrastructure.web`

Purpose:

- public HTTP API

Current type:

- `PublicSellerStoreController`

### `com.bun.platform.sellerstore.infrastructure.events`

Purpose:

- react to product/store changes and evict stale store-page caches

Current type:

- `StorePageCacheInvalidationListener`

## 4. Type Reference

### `SellerStore`

**Kind:** domain record  
**Package:** `com.bun.platform.sellerstore.domain`

#### Description

Represents the read-model view of one public seller store.

#### Responsibilities

- expose store identity and public slug
- expose store branding references
- expose aggregate metrics needed by the public page

#### Key Fields

- `storeId`
- `sellerId`
- `storeName`
- `slug`
- `description`
- `logoImageId`
- `bannerImageId`
- `active`
- `createdAt`
- `theme`
- `totalProducts`
- `activeOfferProductCount`

### `StoreSlug`

**Kind:** value object  
**Package:** `com.bun.platform.sellerstore.domain`

#### Description

Encapsulates slug normalization and validation.

#### Responsibilities

- normalize incoming slug values
- validate slug format
- provide public-path formatting
- provide deterministic slugification for generated store slugs

#### Rules

- lowercase only
- alphanumeric plus hyphen
- no blank slug

### `StoreTheme`

**Kind:** value object  
**Package:** `com.bun.platform.sellerstore.domain`

#### Description

Captures a stable theme code without introducing a full theming engine.

#### Current Role

- preserve forward compatibility for store visual themes
- keep current implementation to a validated string code

### `StorePageFilter`

**Kind:** application DTO  
**Package:** `com.bun.platform.sellerstore.application.dto`

#### Description

Represents caller-supplied filtering input for a store page request.

#### Fields

- `categoryId`
- `minPrice`
- `maxPrice`
- `keyword`

#### Validation Rules

- `minPrice >= 0`
- `maxPrice >= 0`
- `minPrice <= maxPrice`
- blank keyword becomes `null`

### `StoreSummaryDto`

**Kind:** API DTO  
**Package:** `com.bun.platform.sellerstore.application.dto`

#### Description

Represents the public store profile section returned by the API.

#### Fields

- `storeId`
- `sellerId`
- `storeName`
- `slug`
- `publicPath`
- `description`
- `logoImage`
- `bannerImage`
- `active`
- `createdAt`
- `themeCode`
- `totalProducts`
- `activeOfferProductCount`

### `StoreProductCardDto`

**Kind:** API DTO  
**Package:** `com.bun.platform.sellerstore.application.dto`

#### Description

Represents the store product card returned by the public listing.

#### Fields

- `productId`
- `productName`
- `mainImage`
- `defaultVariantEffectivePrice`
- `hasActiveOffer`
- `sellerId`
- `featured`

#### Important rule

`defaultVariantEffectivePrice` always comes from the default variant, never from `ProductDefinition`.

### `StorePageReadRepository`

**Kind:** projection repository  
**Package:** `com.bun.platform.sellerstore.infrastructure.persistence`

#### Description

Owns the read-side SQL for store summary, product cards, filter facets, and cache-eviction lookup helpers.

#### Main queries

- `findStoreSummaryBySlug(String)`
- `findStoreProductCards(String, Long, BigDecimal, BigDecimal, String, Pageable)`
- `findAvailableCategories(String)`
- `findPriceBounds(String)`
- `findSlugBySellerId(Long)`
- `findSlugByProductId(Long)`
- `findSlugByVariantId(Long)`

### `SellerStorePageService`

**Kind:** application service  
**Package:** `com.bun.platform.sellerstore.application`

#### Description

Orchestrates the full public store-page response.

#### Responsibilities

- normalize slug and filter input
- load summary projection
- load paged product cards
- load available category facets
- load store-level price bounds
- map projections into API DTOs
- apply response caching

### `StorePageCacheKeyFactory`

**Kind:** cache-support component  
**Package:** `com.bun.platform.sellerstore.application`

#### Description

Builds a deterministic cache key matching the store-page query shape.

#### Key format

- `store:{slug}:page:{page}:size:{size}:filters:category={...};min={...};max={...};q={...}`

### `StorePageCacheInvalidationService`

**Kind:** cache-support service  
**Package:** `com.bun.platform.sellerstore.application`

#### Description

Provides prefix-based eviction for store page cache entries.

#### Responsibilities

- evict by seller id
- evict by product id
- evict by variant id
- evict by slug

### `StorePageCacheInvalidationListener`

**Kind:** infrastructure event listener  
**Package:** `com.bun.platform.sellerstore.infrastructure.events`

#### Description

Subscribes to product-domain events and evicts affected store-page cache entries after commit.

#### Observed event inputs

- `ProductCreatedEvent`
- `VariantCreatedEvent`
- `ProductUpdatedEvent`
- `ProductActivatedEvent`
- `ProductDeactivatedEvent`
- `ProductDeleteEvent`
- `DefaultVariantChangedEvent`
- `VariantActivatedEvent`
- `VariantDeactivatedEvent`
- `VariantPriceChangedEvent`

### `PublicSellerStoreController`

**Kind:** REST controller  
**Package:** `com.bun.platform.sellerstore.infrastructure.web`

#### Description

Exposes the public store read endpoint.

#### Endpoint

- `GET /api/stores/{slug}`

## 5. Query And Projection Model

### Why projections are used instead of entities

This module intentionally uses projection interfaces and native SQL rather than loading JPA entities for storefront reads.

Reasons:

- store page is read-mostly
- the page needs only a narrow field set
- entity graphs would load unnecessary state
- projections avoid N+1 on variants, tags, and categories
- projections reduce persistence-context overhead
- projections map naturally to cached response assembly

### Store summary query

The summary query reads:

- store profile columns from `stores`
- total active product count
- count of products whose default variant currently has an active offer

It joins only what is needed:

- `stores`
- `product_definitions`
- default `variants`

### Product card query

The product-card query returns:

- `productId`
- `productName`
- `mainImageId`
- `defaultVariantEffectivePrice`
- `hasActiveOffer`
- `sellerId`
- `featured`

It filters by:

- store slug
- active store
- active product
- active default variant
- optional category id
- optional keyword
- optional min/max effective price

### Effective-price projection formula

The query applies the current product-domain pricing contract:

- if active offer exists and is not expired:
  - `greatest(base_price - discount_amount, 0)`
- otherwise:
  - `base_price`

The source fields still live only on `variants`.

### Why `media_items` is not joined for cards

Product and store image URLs are derived from stored UUIDs through `MediaUtil`.

That is intentional because:

- it avoids one more hot-path join
- the public media endpoint already resolves the UUID
- the store page only needs a stable media reference and derived URL

### Keyword search behavior

Current keyword search uses case-insensitive `like` matching against:

- product name
- product description
- category name
- tags

This is a pragmatic choice:

- simple
- predictable
- easy to keep inside one query

It is not yet a full-text-search implementation.

### Facet behavior

Available categories and price bounds are currently store-scoped, not dynamically narrowed by the active keyword/category/price filter combination.

This trade-off was chosen to keep:

- query count low
- cache shape stable
- facet queries simple

If fully dynamic facets are needed later, they should be added as dedicated filtered facet queries keyed by the same cache filter hash.

## 6. Cache Strategy

### Cache name

- `store_page_cache`

### TTL

- `30 minutes`

### Key

- `store:{slug}:page:{page}:size:{size}:filters:category={...};min={...};max={...};q={...}`

### Why page-level response caching is appropriate

Store pages are ideal cache candidates because:

- most reads are public
- product cards change less often than they are viewed
- projection assembly is deterministic
- pagination isolates cache churn

### Eviction policy

Evict store-page cache when:

- store profile changes
- product metadata changes
- product activation changes
- default variant changes
- variant activation changes
- variant price changes

### Prefix-based eviction

The invalidation service removes cache entries by slug prefix rather than needing to know all page and filter combinations in advance.

This is important because filter combinations are open-ended.

## 7. REST API Contract

### Endpoint

- `GET /api/stores/{slug}`

### Query parameters

- `page` default `0`
- `size` default `24`, max `60`
- `categoryId` optional
- `minPrice` optional
- `maxPrice` optional
- `q` optional keyword

### Response shape

`StorePageResponse` contains:

- `store`
- `products`
- `filters`
- `appliedFilters`
- `pagination`

### Response intent

The endpoint is designed for store landing pages and category-like browsing grids, not for full product details.

## 8. Persistence Reference

### Main tables

- `stores`
- `store_featured_products`
- `product_definitions`
- `variants`

### Supporting tables

- `categories`
- `product_tags`
- `tags`

### Migration

The store read model is enabled by:

- `V35__seller_store_read_model.sql`

### Added store columns

- `store_name`
- `slug`
- `description`
- `logo_image_id`
- `banner_image_id`
- `is_active`
- `created_at`
- `updated_at`
- `theme_code`

### Added indexes

- unique slug index on store
- store slug/activity index
- store seller/activity index
- seller/category/created product listing index
- default-variant store listing index
- featured-product ordering indexes

### Featured products modeling choice

`store_featured_products` is currently table-backed only.

There is no dedicated JPA entity for it because the public store page only needs read-time ordering and boolean marking.

That keeps the read model simpler and avoids introducing write-side complexity before a real featured-product management workflow exists.

## 9. Current Invariants

- one seller maps to one store row
- one store slug is globally unique
- store page only reads active stores
- store page only lists active products
- store page only lists products with an active default variant
- product card price is always projected from the default variant
- store module does not mutate product or variant state
- cache entries are scoped by slug plus paging/filter arguments

## 10. Trade-Offs And Design Decisions

### 1. Projection instead of entity loading

Chosen because storefront reads are latency-sensitive and field-narrow.

Benefits:

- less memory churn
- fewer joins through object graphs
- no lazy-loading surprises
- simpler caching

Trade-off:

- native SQL is less reusable than entity-based repositories

### 2. Default variant as the card price source

Chosen because the product domain already defines the default variant as the storefront price anchor.

Benefits:

- no duplicated pricing rule
- no ambiguity when a product has multiple variants
- no risk of product-level price drift

Trade-off:

- if merchandising later wants price ranges, that must be an additional projection, not a replacement for the current card price

### 3. Cache vs database freshness

Chosen design:

- cache full page responses for 30 minutes
- evict aggressively on known write events

Benefits:

- sub-150ms cached reads are realistic
- store page becomes cheap under traffic

Trade-off:

- eviction coverage must stay aligned with write paths
- missing event coverage would produce stale pages

### 4. Read-only store domain

Chosen because the module's job is composition, not ownership.

Benefits:

- respects product-domain boundaries
- avoids turning storefront reads into a second catalog aggregate
- keeps modular-monolith boundaries clear

Trade-off:

- some persistence is still shared with the legacy `store` package

### 5. Simple keyword search instead of FTS

Chosen because it is sufficient for store-scoped browsing and keeps query behavior easy to reason about.

Trade-off:

- less relevance quality than a dedicated FTS index
- may need upgrade if stores become large

## 11. Known Gaps

### Store profile write contract is still legacy-oriented

The current write path for store profile data still lives in `com.bun.platform.store.services.StoreService`.

It now hydrates slug/name/theme defaults and evicts store-page cache, but it is not yet a dedicated seller-store write API.

### Featured-product write workflow is not implemented yet

The table and read ordering support are present, but there is no dedicated seller-facing management service yet.

### Store-level offers are aggregate-only

The current implementation exposes:

- `activeOfferProductCount`

It does not introduce a separate store-offer pricing model.

### Filter facets are not filter-contextual

This is acceptable for now but should be revisited if the UX needs dynamic faceted narrowing.

## 12. Recommended Next Steps

- add explicit seller-store profile write DTOs and endpoints
- add featured-product management use cases
- upgrade keyword search to PostgreSQL FTS if large stores require it
- add filtered facet queries if the frontend needs contextual facet counts
- expose store analytics separately instead of overloading the public page read model
