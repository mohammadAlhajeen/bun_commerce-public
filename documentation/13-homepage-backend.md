# Homepage Backend Reference

## Overview

The homepage backend provides the public storefront landing payload.

It is responsible for:

- returning root categories for homepage navigation;
- returning featured public product cards;
- assembling homepage sections from product, category, collection, static, and hybrid strategies;
- batching product-card hydration through the shared `ProductCard` read path;
- caching the assembled homepage response;
- setting short public HTTP cache headers.

Primary packages:

- `com.bun.platform.catalog.product.controller`
- `com.bun.platform.catalog.product.service`
- `com.bun.platform.catalog.product.dto`

Collaborators:

- `com.bun.platform.catalog.category`
- `com.bun.platform.catalog.product.repository`
- `com.bun.platform.catalog.product.product_dtos.ProductCard`

## Public API

Controller:

- `HomePageController`

Endpoint:

- `GET /api/public/home`

Query parameters:

- `size`
- `categoryPage`
- `categorySize`

HTTP cache behavior:

- `Cache-Control: public, max-age=120`

## Response Contract

The endpoint returns `HomePageDataDto`.

Current fields:

- `categories: List<CategoryRootsProjection>`
- `products: List<ProductCard>`
- `sections: List<HomeSectionDto>`

Important current-contract note:

- there is no top-level `collections` field in `HomePageDataDto`;
- collection-backed content appears through homepage sections;
- products use the standardized public `ProductCard` shape.

## DTOs

### `HomePageDataDto`

```java
public record HomePageDataDto(
        List<CategoryRootsProjection> categories,
        List<ProductCard> products,
        List<HomeSectionDto> sections) {
}
```

### `HomeSectionDto`

Represents one rendered homepage section.

Typical fields:

- `id`
- `strategy`
- `title`
- `description`
- `ctaLabel`
- `ctaHref`
- `products`

### `HomeSectionStrategy`

Current strategy concepts:

- `PRODUCT_BASED`
- `CATEGORY_BASED`
- `COLLECTION_BASED`
- `STATIC`
- `HYBRID`

## Assembly Flow

Homepage assembly is handled by `HomePageService`.

High-level flow:

1. Normalize requested section size and category paging inputs.
2. Load root categories from `CategoryService`.
3. Build product IDs for each section strategy.
4. Union section product IDs into one ordered distinct set.
5. Hydrate all required product cards once through `ProductReadService.getProductCardMap(...)`.
6. Reuse the hydrated map to build each homepage section.
7. Return `HomePageDataDto`.

The important performance rule is: collect IDs first, hydrate cards once.

## Product Card Hydration

The homepage uses the same card path as other public product surfaces:

- `ProductReadService.getProductCardMap(productIds)`
- `ProductCardLookupService.getProductCardMap(productIds)`
- `ProductCardCache.getAll(productIds)`
- `ProductRepository.findCardsByIds(ids)` on cache miss

The returned card type is `ProductCard`, not `ProductCardProjection`.

## Section Sources

### Product-Based Section

Source:

- `ProductReadService.getHomeProductIds(size)`

Behavior:

- prefers products with active offers;
- falls back to general active products if needed;
- only products with active default variants are eligible;
- ordering favors sales count, creation time, and stable product ID fallback.

### Category-Based Section

Source:

- root categories from `CategoryService`;
- product IDs from `ProductReadService.getProductIdsForCategory(...)`.

Behavior:

- expands category descendants through category service helpers;
- only active products with active default variants are eligible.

### Collection-Based Section

Source:

- public active collections;
- product IDs from collection membership ordering.

Behavior:

- only active products inside active, non-deleted collections are returned;
- product cards are hydrated through the shared product-card cache.

### Static Section

Source:

- derived from already selected featured products.

Behavior:

- provides a stable editorial-like block without extra card queries.

### Hybrid Section

Source:

- product-based section;
- category-based section;
- collection-based section.

Behavior:

- merges section IDs;
- preserves first-seen order;
- limits output to the configured section size.

## Cache Layers

### `homepage`

Owner:

- `HomePageService`

Purpose:

- cache the assembled homepage response.

### `ProductCardCache`

Owner:

- catalog product read path.

Purpose:

- cache individual public `ProductCard` records.

### Collection and Category Caches

Collection/category services may cache membership and hierarchy data used during homepage assembly.

## Cache Invalidation

Homepage cache should be invalidated when public homepage-visible catalog state changes, including:

- product create/update/delete;
- product activate/deactivate;
- variant activate/deactivate;
- default variant changes;
- variant price changes;
- offer state changes that affect homepage cards;
- collection create/update/delete;
- collection membership or order changes;
- category changes that affect section navigation or category-backed sections.

## Current Invariants

- homepage products are public `ProductCard` records;
- card hydration is batched;
- section construction reuses the same hydrated card map;
- response is public and short-cacheable;
- homepage response does not expose seller/admin-only product fields.

## Recommended Next Steps

- Add examples of the JSON response once the public demo data is stable.
- Keep `13-homepage-uml.md` aligned with the `ProductCard` shape.
- Add cache-hit metrics for homepage and product-card hydration.
- Add admin-configurable homepage section definitions if editorial control becomes a requirement.
