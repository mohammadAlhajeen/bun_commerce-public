# Current Architecture Refactor

**Source branch:** `refactoer-and-redy-to-module`  
**Purpose:** public documentation snapshot for the current commerce read model, storefront catalog, seller store page, and search architecture.

This page exists because several older domain documents were written before the latest refactor. Treat this as the current high-level source of truth for the newest architecture.

## Summary

The latest architecture moves the platform toward a cleaner read model:

- one standardized public `ProductCard` shape is reused by product listing, search, collections, homepage, and seller store pages;
- store pages no longer adapt product cards into a store-specific product DTO;
- product and store search use PostgreSQL full-text search for Arabic and English text;
- global search combines product and store results behind one public endpoint;
- storefront catalog facets and product cards have separate cache boundaries;
- homepage payloads hydrate product cards through the same shared card cache;
- seller product management uses a separate seller-facing card/query model.

## Standard Product Card

`ProductCard` is the public storefront card record for product tiles and rails.

Current fields:

- `id`
- `name`
- `description`
- `mainImageId`
- `isActive`
- `salesCount`
- `currency`
- `variantId`
- `basePrice`
- `discountAmount`
- `offerEndsAt`
- `offerType`
- `hasRequiredAttributes`

Computed helpers:

- `effectivePrice()` computes `basePrice - discountAmount`, never below zero.
- `hasActiveOffer()` checks positive discount and unexpired offer time.
- `mainImageUrl()` derives the public media URL from `mainImageId`.

Important consequences:

- public endpoints return `ProductCard` directly;
- store pages return `List<ProductCard>` inside `StorePageResponse`;
- the old `StoreProductCardDto` adapter is removed from the current response shape;
- frontend store pages consume the shared `CatalogProductCard` type instead of a store-specific card shape;
- seller identity is read from the store context, not from each product card.

## Product Card Cache

`ProductCardCache` is the primary cache for public product cards.

Configuration:

- maximum size: `15,000`
- TTL: `32 minutes`
- implementation: Caffeine `LoadingCache`

Behavior:

- single misses load through `ProductRepository.findCardById(id)`;
- bulk misses load through `ProductRepository.findCardsByIds(ids)`;
- bulk lookup preserves input order;
- missing cards are omitted from bulk results;
- `ProductCardLookupService` normalizes IDs by removing `null` values and duplicates before lookup.

This makes all public card consumers share the same read model and cache path.

## Storefront Catalog Read Model

The storefront catalog layer lives in `com.bun.platform.catalog.product.storefront`.

Main types:

- `StorefrontCatalogQuery`
- `StorefrontCatalogQueryService`
- `StorefrontCatalogPage`
- `StorefrontCatalogMetrics`
- `StorefrontCollectionFacet`
- `StorefrontCategoryFacet`
- `StorefrontPriceBounds`
- `StorefrontFacetCache`

Flow:

1. Normalize the query and pageable.
2. Query a page of product IDs from `StorefrontCatalogReadRepository`.
3. Hydrate the IDs through `ProductCardLookupService`.
4. Return `StorefrontCatalogPage` containing:
   - `Page<ProductCard>`
   - collection facets
   - category facets
   - price bounds
   - store metrics

The repository reads from `storefront_product_cards`, a buyer-facing database view.

Supported store-page filters:

- `collectionId`
- `categoryId`
- `minPrice`
- `maxPrice`
- `keyword`
- `sort`
- `page`
- `size`

Sort options currently support newest-first plus price ascending/descending behavior through repository ordering.

## Storefront Facet Cache

`StorefrontFacetCache` keeps store-level filter data separate from product-card caching.

| Cache | Key | Size | TTL |
| --- | --- | ---: | --- |
| collections | `storeId` | 1,000 | 10 minutes |
| categories | `storeId:collectionId` | 2,000 | 10 minutes |
| price bounds | `storeId:collectionId` | 2,000 | 5 minutes |
| metrics | `storeId` | 1,000 | 5 minutes |

`evictStore(storeId)` clears collections, metrics, and all collection-scoped category/price-bound entries for one store.

## Seller Store Page

The seller-store module still owns public store profile composition, but it no longer owns product-card shaping.

Current flow:

1. `PublicSellerStoreController` receives `GET /api/stores/{slug}`.
2. `SellerStorePageService` normalizes the slug, filters, and pageable.
3. It loads the active store profile by slug.
4. It delegates product listing and facets to `StorefrontCatalogQueryService`.
5. It returns `StorePageResponse`.

`StorePageResponse` contains:

- `store: StoreSummaryDto`
- `products: List<ProductCard>`
- `filters: StoreAvailableFiltersDto`
- `appliedFilters: StoreAppliedFiltersDto`
- `pagination: StorePaginationDto`

`StoreSummaryDto` also carries public store metadata such as:

- logo and banner media references;
- total products;
- active-offer product count;
- total sales count;
- SEO data;
- navigation links;
- social links.

Page-level cache:

- cache name: `store_page_cache`
- key prefix: `store:{slug}:...`
- invalidation removes all keys for the store slug when product/store events affect that page.

## Seller Store Cache Invalidation

`StorePageCacheInvalidationListener` listens after transaction commit for product-domain events:

- product created
- product updated
- product activated/deactivated
- product deleted
- variant created
- variant activated/deactivated
- default variant changed
- variant price changed

The listener resolves the affected store and evicts the public store page cache prefix for that store.

This cache is separate from `StorefrontFacetCache` and `ProductCardCache`.

## Seller Catalog Read Model

Seller-facing product management does not use the same exact response shape as public storefront cards.

The seller read model uses:

- `SellerProductCard`
- `SellerProductCardProjection`
- `SellerCatalogQuery`
- `SellerCatalogQueryService`
- `SellerProductReadRepository`

This model includes management fields such as activity state, category ID, default-variant status, and timestamps that are not needed on public product cards.

## Product Search

Product search now routes through `ProductSearchEngine` and returns product IDs first.

Main pieces:

- `PostgresProductSearchEngine`
- `SearchEngineRouter`
- `ProductSearchResultCache`
- `SearchQueryNormalizer`
- `ProductReadService.searchActiveProductCards(...)`

Current PostgreSQL behavior:

- keyword-only full-text search with pagination;
- uses `product_search.fts_all`;
- ranks with `ts_rank`;
- filters to active, non-deleted products with an active default variant;
- hydrates ranked IDs through the shared `ProductCard` cache.

`ProductSearchResultCache`:

- caches ranked product-ID pages only;
- key: normalized query + page + size;
- TTL: `60 seconds`;
- max entries: `2,000`;
- product card hydration remains separate so price/offer cards still flow through `ProductCardCache`.

`SearchQueryNormalizer` canonicalizes query text for cache keys. It safely normalizes casing, whitespace, Arabic letter forms, Arabic digits, diacritics, zero-width characters, and Latin accents. PostgreSQL remains the authoritative search normalizer.

## Store Search

Store search lives in the seller-store application layer:

- `StoreSearchService`
- `StoreSearchReadRepository`
- `StoreSearchProjection`
- `StoreSearchResult`

It searches active stores using `stores.search_vector`, a generated tsvector column.

Returned store-search fields:

- `storeId`
- `storeName`
- `slug`
- `publicPath`
- `description`
- `logoImage`
- `totalProducts`

Pagination is clamped to a maximum size of `60`.

## Global Search

Global search lives in `com.bun.platform.search` so catalog and seller-store do not depend on each other directly.

Endpoint:

- `GET /api/public/search`

Query parameters:

- `q`: search text
- `type`: optional section selector, `product` or `store`
- `page`: zero-based page number
- `size`: requested page size

Response:

- `UnifiedSearchResponse`
  - `query`
  - `products: SearchPage<ProductCard>`
  - `stores: SearchPage<StoreSearchResult>`

Modes:

- no `type`: preview mode, returns up to 8 products and 5 stores;
- `type=product`: full paginated product results, store section empty;
- `type=store`: full paginated store results, product section empty.

## Full-Text Search Persistence

Migration `V12__activate_fts_search.sql` activates the FTS infrastructure.

Product search:

- aligns `product_search.product_id` with product IDs;
- adds a GIN index on `product_search.fts_all`;
- defines `refresh_product_search(product_id)`;
- backfills existing products;
- adds triggers for product rows, product tags, category name changes, and store name changes.

Store search:

- adds `stores.search_vector`;
- computes it from `store_name` and `description`;
- indexes it with GIN.

Both products and stores use the bilingual `ar_en_tsvector` / `ar_en_tsquery` functions from earlier migrations.

## Homepage Read Model

Homepage data now uses the same `ProductCard` shape.

`HomePageDataDto` contains:

- `categories`
- `products: List<ProductCard>`
- `sections`

`HomePageController`:

- endpoint: `GET /api/public/home`;
- accepts `size`, `categoryPage`, and `categorySize`;
- sets `Cache-Control: public, max-age=120`.

`HomePageService` collects product IDs from multiple section strategies, hydrates them once through `ProductReadService.getProductCardMap(...)`, and then assembles the final homepage sections.

## Current Cache Boundaries

| Cache | Owner | Stores | Purpose |
| --- | --- | --- | --- |
| `ProductCardCache` | catalog product service | `ProductCard` by product ID | shared public card hydration |
| `ProductSearchResultCache` | product search | ranked product ID pages | cheap FTS page reuse |
| `StorefrontFacetCache` | storefront catalog | collections/categories/price/metrics | filter metadata |
| `store_page_cache` | seller-store page service | full public store page responses | page-level response reuse |
| `homepage` | homepage service | full homepage payload | short-lived homepage response reuse |

The important architectural rule is that product cards, search ID pages, facets, store pages, and homepage payloads are cached independently.

## Public Documentation Caveat

This repository documents the current architecture but does not contain the private source code. It should not be treated as a runnable application.
