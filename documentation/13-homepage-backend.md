# Homepage Backend Reference

## Overview

The homepage backend provides the public landing payload used by the storefront root page.

It is responsible for:

- returning root categories for homepage navigation
- returning featured product cards
- returning featured public collections
- assembling multiple homepage section strategies
- batching product-card hydration for homepage traffic
- caching the assembled homepage response
- invalidating homepage cache when catalog state changes

Primary packages:

- `com.bun.platform.catalog.product.controller`
- `com.bun.platform.catalog.product.service`
- `com.bun.platform.catalog.product.dto`

Collaborating packages:

- `com.bun.platform.catalog.category`
- `com.bun.platform.catalog.product.repository`

## Public API

### Controller

**Controller:** `HomePageController`  
**Base path:** `/api/public/home`

### Endpoint

- `GET /api/public/home`

### Query Parameters

- `size` optional integer

### Response Contract

The endpoint returns `HomePageDataDto`.

Top-level fields:

- `categories`
- `products`
- `collections`
- `sections`

### HTTP Cache Behavior

The controller sets public cache headers:

- `Cache-Control: public, max-age=120`

This allows short-lived CDN or reverse-proxy reuse while keeping the payload reasonably fresh.

## DTO Reference

### `HomePageDataDto`

Top-level homepage payload.

Fields:

- `categories: List<CategoryRootsProjection>`
- `products: List<ProductCardProjection>`
- `collections: List<HomeCollectionSummaryDto>`
- `sections: List<HomeSectionDto>`

### `HomeCollectionSummaryDto`

Minimal collection block used by the homepage.

Fields:

- `id`
- `name`
- `slug`
- `description`
- `imageUrl`

### `HomeSectionDto`

Represents one rendered homepage section.

Fields:

- `id`
- `strategy`
- `title`
- `description`
- `ctaLabel`
- `ctaHref`
- `products`

### `HomeSectionStrategy`

Current enum values:

- `PRODUCT_BASED`
- `CATEGORY_BASED`
- `COLLECTION_BASED`
- `STATIC`
- `HYBRID`

## Assembly Flow

Homepage assembly is handled by `HomePageService`.

Execution flow:

1. normalize the requested section size
2. load root categories from `CategoryService`
3. load featured public collections from `ProductCollectionRepository`
4. build a lightweight section index using product IDs only
5. union all homepage product IDs into one distinct ordered set
6. hydrate product cards in one cache-aware batch through `ProductReadService`
7. construct homepage sections from the hydrated card map
8. return one `HomePageDataDto`

This keeps homepage reads predictable under traffic because the service avoids repeated card loading per section.

## Section Strategies

### Product-Based Section

Source:

- `ProductReadService.getHomeProductIds(size)`

Behavior:

- uses active products only
- orders by `salesCount`, then `createdAt`, then `id`
- reuses the hydrated product-card map

### Category-Based Section

Source:

- root categories from `CategoryService.getAllRoots()`
- product IDs from `ProductReadService.getProductIdsForCategory(...)`

Behavior:

- homepage currently takes the first two root categories
- category expansion includes child categories through `CategoryService.findCategoryWithAllChildrenIds(...)`
- only active products with an active default variant are eligible

### Collection-Based Section

Source:

- public active collections from `ProductCollectionRepository.findByIsActiveTrueOrderByCreatedAtDesc(...)`
- product IDs from `CollectionService.getCollectionProductIds(...)`

Behavior:

- homepage currently takes the first two featured collections
- collection product order follows collection item sort order
- only active products inside active, non-deleted collections are returned

### Static Section

Source:

- derived from featured homepage products

Behavior:

- selects alternating items from the featured product list
- acts as a stable editorial block without extra repository reads

### Hybrid Section

Source:

- product-based section
- first category-based section
- first collection-based section

Behavior:

- merges multiple strategy results into one ordered unique list
- preserves first-seen order
- limits the final result to the configured section size

## Read Path Performance Model

### Batch ID Collection

The homepage does not fetch each section as fully hydrated product cards independently.

Instead it:

- collects IDs per section first
- unions all IDs into one ordered distinct set
- hydrates cards once

This removes repeated repository and cache work when the same product appears in more than one section.

### Product Card Hydration

`ProductReadService.getProductCardMap(...)` is the key hot-path optimization.

Behavior:

- checks `product_card` cache for each requested product ID
- accumulates cache misses
- loads all misses in one repository call through `ProductRepository.findCardsByIds(...)`
- writes loaded cards back into `product_card`
- returns an ID-keyed map for reuse by callers

This is the main change that makes homepage traffic cheaper than repeated `getProductCard(id)` calls.

### Collection Reads

`CollectionService.getCollectionProductCards(...)` now:

- reads collection product IDs from the collection cache
- hydrates cards through the same batch-aware `ProductReadService`
- logs at `debug` level instead of `info` for public reads

That reduces both DB load and log noise under high traffic.

## Cache Layers

### `homepage`

Used by:

- `HomePageService.getHomePageData(...)`

Purpose:

- cache the fully assembled homepage payload

### `product_card`

Used by:

- `ProductReadService.getProductCard(...)`
- `ProductReadService.getProductCardMap(...)`

Purpose:

- cache individual product-card projections

### `product_card_collections`

Used by:

- `ProductCacheService.getCollectionProductIds(...)`

Purpose:

- cache ordered collection membership as product IDs only

### `categorie_attributs`

Used by:

- category root and tree reads

Purpose:

- cache root categories and derived category hierarchies used by homepage assembly

## Cache Invalidation

### Homepage Cache Service

`HomePageCacheService` provides a focused invalidation path for the `homepage` cache.

### Product Event Invalidation

`ProductEventListener` clears homepage cache after relevant product events, including:

- product created
- product activated
- product deactivated
- product updated
- product deleted
- variant created
- variant activated
- variant deactivated
- default variant changed
- product price changed
- variant price changed
- availability changed
- invariant violation

For product-bound changes it also evicts:

- `product_cache`
- `product_card`

### Collection Mutation Invalidation

`CollectionService` clears homepage cache after:

- collection create
- collection update
- collection activation and deactivation
- collection delete
- add product to collection
- remove product from collection
- reorder collection items
- update item sort order

### Category Mutation Invalidation

`CategoryService` clears homepage cache after:

- category create
- category update
- category delete

## Repository Rules

### Homepage Product IDs

`ProductRepository.findHomeProductIds(...)` returns:

- active products only
- products with an active default variant
- descending order by `salesCount`, then `createdAt`, then `id`

### Category Product IDs

`ProductRepository.findActiveProductIdsByCategoryIds(...)` returns:

- active products only
- category-scoped product IDs
- only products with an active default variant

### Batched Card Read

`ProductRepository.findCardsByIds(...)` returns:

- public card projection data only
- active products only
- default active variant price state only

This query is intentionally projection-based and does not load full entities.

## Operational Notes

### Good Fit

This homepage backend is optimized for:

- public anonymous traffic
- repeated reads with short freshness windows
- overlapping product appearance across sections
- cache-friendly storefront rendering

### Current Limits

Current homepage behavior is still fixed in service code:

- first two root categories only
- first two public collections only
- first three featured collections loaded for summary
- one homepage payload shape for all users

There is no CMS-driven section configuration yet.

### Scaling Direction

If traffic grows further, the next backend steps would be:

- add explicit metrics for homepage cache hit ratio
- add CDN cache keys and stale-while-revalidate policy at the edge
- precompute homepage section indexes asynchronously
- add payload trimming for clients that only need selected blocks
- move homepage strategy configuration into persistent admin-managed data

## Related Code

Primary code locations:

- `src/main/java/com/bun/platform/catalog/product/controller/HomePageController.java`
- `src/main/java/com/bun/platform/catalog/product/service/HomePageService.java`
- `src/main/java/com/bun/platform/catalog/product/service/HomePageCacheService.java`
- `src/main/java/com/bun/platform/catalog/product/service/ProductReadService.java`
- `src/main/java/com/bun/platform/catalog/product/service/CollectionService.java`
- `src/main/java/com/bun/platform/catalog/product/event/ProductEventListener.java`
- `src/main/java/com/bun/platform/catalog/product/repository/ProductRepository.java`
- `src/main/java/com/bun/platform/catalog/product/repository/ProductCollectionRepository.java`
