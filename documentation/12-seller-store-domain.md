# Seller Store Domain

## Overview

The `sellerstore` module owns public seller-store page composition and seller-store profile concerns.

It no longer owns product-card shaping. Product listing and filter data for public store pages are delegated to the catalog storefront read model, which returns standardized `ProductCard` records.

Primary package:

- `com.bun.platform.sellerstore`

Important collaborators:

- `com.bun.platform.catalog.product.storefront`
- `com.bun.platform.catalog.product.product_dtos.ProductCard`
- `com.bun.platform.catalog.product.search`
- `com.bun.platform.search`

## Responsibilities

The seller-store module is responsible for:

- resolving active public stores by slug;
- composing public store profile metadata;
- exposing public store page responses;
- accepting store-page filters and pagination;
- returning SEO, navigation, and social link metadata;
- caching full public store page responses;
- invalidating public store page cache after product/store changes;
- searching active stores for global search.

It is not responsible for:

- product writes;
- product card field mapping;
- product price calculation;
- offer rules;
- inventory reservation;
- product search ranking.

## Current Public Store Page Flow

Endpoint:

- `GET /api/stores/{slug}`

Flow:

1. `PublicSellerStoreController` receives the slug, filters, and pageable input.
2. `SellerStorePageService` normalizes the slug through `StoreSlug`.
3. It normalizes `StorePageFilter`.
4. It loads an active store profile by slug.
5. It calls `StorefrontCatalogQueryService.getStorefrontPage(...)`.
6. It returns `StorePageResponse`.

`SellerStorePageService` does not convert product cards into a store-specific product DTO.

## StorePageResponse

Current response shape:

```java
public record StorePageResponse(
        StoreSummaryDto store,
        List<ProductCard> products,
        StoreAvailableFiltersDto filters,
        StoreAppliedFiltersDto appliedFilters,
        StorePaginationDto pagination) {
}
```

The important architecture change is:

- old: store page product cards were adapted into `StoreProductCardDto`;
- current: store page product cards are returned directly as `ProductCard`.

This keeps `/api/stores/{slug}`, `/api/public/products`, public collections, homepage sections, and global product search aligned around one public product-card shape.

## StorePageFilter

Supported filters:

- `collectionId`
- `categoryId`
- `minPrice`
- `maxPrice`
- `keyword`
- `sort`

Validation/normalization:

- blank keyword becomes `null`;
- `minPrice` and `maxPrice` must be non-negative;
- `minPrice` cannot be greater than `maxPrice`;
- missing sort defaults to `NEWEST`.

## Store Summary

`StoreSummaryDto` exposes public store identity and display metadata:

- store ID;
- seller ID;
- store name;
- slug and public path;
- description;
- logo and banner media;
- active state;
- created/updated timestamps;
- theme code;
- total product count;
- active-offer product count;
- total sales count;
- SEO metadata;
- navigation links;
- social links.

## Storefront Catalog Delegation

Seller-store delegates product listing to the catalog storefront read model:

- `StorefrontCatalogQuery`
- `StorefrontCatalogQueryService`
- `StorefrontCatalogPage`
- `StorefrontCatalogReadRepository`
- `StorefrontFacetCache`

The seller-store service passes:

- store ID from the resolved store profile;
- collection/category/price/keyword/sort filters;
- normalized pageable.

The catalog layer returns:

- `Page<ProductCard>`;
- collection facets;
- category facets;
- price bounds;
- store metrics.

## Product Card Boundary

The public store page does not own product-card fields.

`ProductCard` owns:

- public product identity;
- default variant ID;
- base price;
- discount amount;
- offer end time;
- offer type;
- active offer calculation;
- effective price calculation;
- main image URL derivation.

Frontend store pages should use the shared product-card type and get seller/store context from `StoreSummaryDto`, not from each product card.

## Store Page Cache

Full public store pages are cached in:

- cache name: `store_page_cache`

Keying:

- keys start with `store:{slug}:`
- the key includes paging and filter state through `StorePageCacheKeyFactory`

Invalidation:

- `StorePageCacheInvalidationService.evictByStoreId(storeId)` resolves the slug and evicts by prefix;
- if native Caffeine prefix eviction is unavailable, the cache is cleared as a fallback.

Events that evict store pages after commit:

- `ProductCreatedEvent`
- `ProductUpdatedEvent`
- `ProductActivatedEvent`
- `ProductDeactivatedEvent`
- `ProductDeleteEvent`
- `VariantCreatedEvent`
- `VariantActivatedEvent`
- `VariantDeactivatedEvent`
- `DefaultVariantChangedEvent`
- `VariantPriceChangedEvent`

## Store Search

Store search supports the global search endpoint.

Main types:

- `StoreSearchService`
- `StoreSearchReadRepository`
- `StoreSearchProjection`
- `StoreSearchResult`

`StoreSearchService.search(keyword, page, size)`:

- rejects blank keywords with an empty page;
- clamps page number to `>= 0`;
- clamps size to a maximum of `60`;
- maps projections into `StoreSearchResult`;
- derives public path from `StoreSlug`;
- derives logo URL through `MediaUtil`.

`StoreSearchReadRepository` searches active stores:

- source: `stores.search_vector`;
- query: `stores.search_vector @@ ar_en_tsquery(:q)`;
- ranking: `ts_rank(stores.search_vector, ar_en_tsquery(:q)) desc`;
- result includes active product count per store.

## StoreSearchResult

Current global-search store result:

```java
public record StoreSearchResult(
        Long storeId,
        String storeName,
        String slug,
        String publicPath,
        String description,
        MediaUrlWithId logoImage,
        long totalProducts) {
}
```

## Persistence Notes

Store page profile state is persisted in `stores`.

Store search uses:

- generated column: `stores.search_vector`;
- GIN index: `idx_stores_search_vector`;
- bilingual text functions: `ar_en_tsvector` and `ar_en_tsquery`.

The store search vector is generated from:

- `store_name`
- `description`

## Current Invariants

- only active stores are public;
- public store pages resolve by normalized slug;
- one store page response uses one store profile;
- product listing is scoped to the resolved store ID;
- products are active storefront `ProductCard` records from the catalog module;
- seller-store does not calculate prices;
- seller-store does not mutate product state;
- store search only returns active stores.

## Trade-Offs

### Store Page Cache vs Product Card Cache

The system keeps full-page store cache separate from individual product-card cache.

Benefit:

- full store pages are cheap for repeated public browsing;
- product cards remain reusable across home, collection, search, and store pages.

Trade-off:

- product mutations must evict both the relevant product-card/facet caches and affected store-page cache entries.

### Store Search Uses FTS, Store Page Keyword Filter Still Uses Listing Query

Global store search uses FTS through `stores.search_vector`.

Store page product filtering still goes through the storefront catalog listing query and its product-card view. This keeps store browsing and global search as separate use cases.

### Product Cards Are Owned By Catalog

The store page no longer adapts product card field names.

Benefit:

- one public card contract across the product surface.

Trade-off:

- frontend code must compute presentation helpers from `ProductCard` fields rather than relying on store-specific convenience fields.

## Recommended Next Steps

- Keep `12-seller-store-uml.md` aligned with this response shape.
- Add explicit docs for seller-store write/update endpoints if those become a first-class module.
- Add store-search examples once public API examples are added.
- Decide whether store page keyword filtering should eventually reuse FTS or remain a scoped listing filter.
