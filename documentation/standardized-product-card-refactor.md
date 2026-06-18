# Standardized Product Card Refactor

> Current-status note: this document is a historical refactor log. For the latest consolidated architecture, including FTS product/store search and global search, read [Current Architecture Refactor](14-current-architecture-refactor.md).

**Branch:** `refactoer-and-redy-to-module`
**Commits:** `bb3a5ad` → `e600a34` → `e6fe5af` → storefront implementation
**Date:** 2026-06-16

---

## Overview

Four sequential changes replaced scattered, duplicated product card query logic with a unified, layered architecture. The end result is two read-model shapes (`ProductCard` for storefront, `SellerProductCard` for the seller dashboard), each backed by a dedicated DB view, repository, query service, and cache — all sharing a single source of truth at the database level. The final step removed the adapter DTO that was bridging the old store-page API and updated the Next.js storefront to consume `ProductCard` directly.

---

## Commit 1 — Foundation and Store Profile Fix (`bb3a5ad`)

### What changed

**`SellerController` / `AdminSellerController`**
- Added `@RequestParam Long storeId` to the `updateMyStore` endpoint on both controllers.
- `storeService.updateStoreProfile(sellerId, request)` → `storeService.updateStoreProfile(storeId, sellerId, request)` — store identity is now explicit, not inferred from the seller.

**`ProductCardCache`** _(new service)_
- Introduced a dedicated `ProductCardCache` backed by Caffeine (`maximumSize=15_000`, `expireAfterWrite=32m`).
- Supports single-get, bulk `getAll` (preserves order), `invalidate`, and `invalidateAll`.
- `loadAll` fetches missing cards from `ProductRepository.findCardsByIds()` in one batch query.

**`ProductCardLookupService`**
- Delegated all cache interactions to `ProductCardCache`; removed its own cache management.

**`ProductCacheService`**
- Consolidated around `ProductCardCache`; removed redundant cache definitions.

**`CollectionService`**
- Significantly simplified (~401 lines reduced); collection product card lookups now go through the unified lookup service rather than ad-hoc queries.

**`ProductVariantService`, `VariantService`, `ProductService`**
- Internal cleanups; event payloads standardized.

**`SellerStoreService`**
- Expanded: now accepts `storeId` in `updateStoreProfile`, allowing multi-store sellers.

**`ShipmentService`**
- Major restructure (~450 lines reorganized), aligned naming and response shapes.

**SQL Migrations (V4–V8)**
- Schema adjustments to support the new read patterns: added `store_id` propagation, price denormalization fields, and corrected index definitions.

**Documentation**
- Updated `02-product-domain.md`, `03-offer-domain.md`, `08-cart-domain.md` through `12-seller-store-domain.md` and cart subdocs to reflect the new shapes and endpoints.

---

## Commit 2 — Storefront Read Model (`e600a34`)

### New types

| Class / Record | Package | Purpose |
|---|---|---|
| `ProductCard` | `product_dtos` | Unified storefront product card record |
| `StorefrontCatalogQueryService` | `storefront` | Entry point for all storefront catalog page queries |
| `StorefrontCatalogPage` | `storefront` | Page result: products + all facets + metrics |
| `StorefrontCatalogQuery` | `storefront` | Query params: storeId, collectionId, categoryId, price range, keyword, sort |
| `StorefrontCatalogMetrics` | `storefront` | Aggregate: total products, active-offer count, total sales |
| `StorefrontCategoryFacet` | `storefront` | categoryId, name, slug, productCount |
| `StorefrontCollectionFacet` | `storefront` | collectionId, name, productCount |
| `StorefrontPriceBounds` | `storefront` | minEffectivePrice, maxEffectivePrice |
| `StorefrontCatalogReadRepository` | `repository` | JPA read-only repo against the new DB view |
| `StorefrontCatalogMetricsProjection` | `repository` | JDBC projection for metrics |
| `StorefrontCategoryFacetProjection` | `repository` | JDBC projection for category facets |
| `StorefrontCollectionFacetProjection` | `repository` | JDBC projection for collection facets |
| `StorefrontPriceBoundsProjection` | `repository` | JDBC projection for price bounds |

### `ProductCard` record

```java
public record ProductCard(
        Long id, String name, String description,
        UUID mainImageId, Boolean isActive, Integer salesCount,
        String currency, Long variantId,
        BigDecimal basePrice, BigDecimal discountAmount,
        Instant offerEndsAt, String offerType,
        boolean hasRequiredAttributes) {

    public BigDecimal effectivePrice() { ... }   // computed from offer fields
    public boolean hasActiveOffer()    { ... }   // checks discount + expiry
    public String mainImageUrl()       { ... }   // MediaUtil.url(mainImageId)

}
```

Current branch note: search and listing flows hydrate product IDs through `ProductCardLookupService` instead of adapting separate search result card types.

The record is self-contained — `effectivePrice()` and `hasActiveOffer()` are computed from the fields it already holds, so no joins are needed at the application layer.

### `StorefrontCatalogQueryService` flow

```
getStorefrontPage(query, pageable)
  ├── normalize(query)   — validates storeId, strips blank keyword, defaults sort to "newest"
  ├── normalize(pageable) — defaults to page 0, size 24
  ├── readRepository.findStoreProductIds(...)  → Page<Long>  (IDs only)
  ├── productCardLookupService.getProductCardsByIds(ids)  → List<ProductCard>  (from cache)
  └── facetCache.getCollections / getCategories / getPriceBounds / getMetrics
```

ID-first pagination: the DB returns a page of product IDs; the cards are resolved from the in-memory `ProductCardCache` — avoiding a N-column join per page.

### Deleted

- `ProductSearchCardView` — replaced entirely by `ProductCard`.
- `StoreProductCardProjection`, `StorePriceBoundsProjection`, `StoreCategoryFacetProjection`, `StoreCollectionFacetProjection`, `StoreSummaryProjection` — all replaced by the storefront-owned projections.
- Storefront facet and metric invalidation moved into `StorefrontFacetCache`. The current branch still keeps `StorePageCacheInvalidationService` for full `store_page_cache` eviction by store slug prefix.

### Controllers updated

- `PublicCollectionController` — returns `List<ProductCard>` instead of `List<ProductCardProjection>`.
- `PublicProductController` — uses `ProductCard` throughout.
- `SellerProductController` — minor alignment.

### Tests updated

- `PublicProductControllerTest`, `PostgresProductSearchEngineTest`, `ProductCardLookupServiceTest`, `ProductReadServiceTest`, `SellerStorePageServiceTest`, `HomePageServiceTest` — all rewritten against the new types.

---

## Commit 3 — Seller Read Model + DB Views + Facet Cache (`e6fe5af`)

### New types

| Class / Record | Package | Purpose |
|---|---|---|
| `SellerProductCard` | `seller` | Seller-facing product card record (includes `isActive`, `createdAt`, `updatedAt`) |
| `SellerProductCardProjection` | `seller` | JDBC projection for `seller_product_cards` view |
| `SellerCatalogQuery` | `seller` | Query params: storeId, isActive filter, categoryId, keyword, sort |
| `SellerCatalogQueryService` | `seller` | Entry point for seller product list queries |
| `SellerProductReadRepository` | `repository` | JPA read-only repo against `seller_product_cards` view |
| `StorefrontFacetCache` | `storefront` | Caffeine cache for storefront facets and metrics |

### `SellerProductCard` vs `ProductCard`

| Field | `ProductCard` (storefront) | `SellerProductCard` (seller) |
|---|---|---|
| `isActive` | Yes (Boolean) | Yes (boolean) |
| `createdAt` / `updatedAt` | No | Yes |
| `categoryId` | No | Yes |
| `variantIsActive` | No | Yes |
| `effectivePrice` | Computed method | Pre-computed field (from view) |
| `offerEndsAt` / `offerType` | Yes | No |
| `hasRequiredAttributes` | Yes | No |

The seller card includes management fields not needed on the public storefront; the storefront card includes offer timing fields not needed in the seller dashboard.

### `StorefrontFacetCache`

Separate Caffeine caches for each facet type, all backed by `StorefrontCatalogReadRepository`:

| Cache | Key | Size | TTL |
|---|---|---|---|
| `collectionsCache` | `storeId` | 1 000 | 10 min |
| `categoriesCache` | `"storeId:collectionId"` | 2 000 | 10 min |
| `priceBoundsCache` | `"storeId:collectionId"` | 2 000 | 5 min |
| `metricsCache` | `storeId` | 1 000 | 5 min |

`evictStore(storeId)` invalidates all four caches for a given store atomically (called on product activate/deactivate, collection changes, offer apply/expire).

### Migration `V11__storefront_product_cards_view.sql`

**New indexes:**

```sql
-- Stable keyset pagination on the listing query
CREATE INDEX idx_product_store_active_listing
    ON product_definitions (store_id, category_id, created_at DESC, id DESC)
    WHERE deleted = false AND is_active = true;

-- Index-only scan for default variant lookup
CREATE INDEX idx_variant_default_active_product
    ON variants (product_definition_id)
    INCLUDE (id, base_price, discount_amount, active_offer_id, offer_ends_at, offer_type)
    WHERE deleted = false AND is_default = true AND is_active = true;

-- Bidirectional collection membership indexes
CREATE INDEX idx_collection_items_product_collection ON product_collection_items (product_id, collection_id);
CREATE INDEX idx_collection_items_collection_product ON product_collection_items (collection_id, product_id);

-- Partial index on active collections
CREATE INDEX idx_collections_store_active
    ON product_collections (store_id, id)
    WHERE deleted = false AND is_active = true;
```

**`storefront_product_cards` view (buyer-facing):**
- `INNER JOIN variants` — only products with an active default variant appear.
- Pre-computes `effective_price` and `has_active_offer` (offer validity checked at DB time).
- Exposes `has_required_attributes` via a correlated `EXISTS` on `variant_attributes`.
- Does NOT expose `is_active` (view already filters to active-only).

**`seller_product_cards` view (seller-facing):**
- `LEFT JOIN variants` — products with no valid default variant still appear so sellers can fix them.
- Pre-computes `effective_price` and `has_active_offer`.
- Exposes `is_active` and `variant_is_active` so sellers see listing status.
- Does NOT filter on `is_active` — sellers need to see inactive products.

### `StorefrontCatalogReadRepository` queries (all native, against the view)

| Method | Returns | Description |
|---|---|---|
| `findStoreProductIds(...)` | `Page<Long>` | Paginated ID list with keyword/price/category/collection filters and sort |
| `findAvailableCollections(storeId)` | `List<StorefrontCollectionFacetProjection>` | Active collections with product counts |
| `findAvailableCategories(storeId, collectionId)` | `List<StorefrontCategoryFacetProjection>` | Categories with product counts, scoped to collection |
| `findPriceBounds(storeId, collectionId)` | `Optional<StorefrontPriceBoundsProjection>` | Min/max effective price |
| `findStoreMetrics(storeId)` | `Optional<StorefrontCatalogMetricsProjection>` | Total products, active-offer count, total sales |

### `SellerProductReadRepository` query

```sql
select ... from seller_product_cards s
where s.store_id = :storeId
  and (:isActive is null or s.is_active = :isActive)
  and (:categoryId is null or s.category_id = :categoryId)
  and (:keyword is null
       or lower(s.product_name) like lower(concat('%', :keyword, '%'))
       or lower(coalesce(s.description, '')) like lower(concat('%', :keyword, '%')))
order by
  case when :sort = 'price_asc'  then s.effective_price end asc,
  case when :sort = 'price_desc' then s.effective_price end desc,
  s.product_created_at desc, s.product_id desc
```

Returns `Page<SellerProductCardProjection>`, mapped to `Page<SellerProductCard>` by `SellerCatalogQueryService`.

### `ProductService` update

Wired `StorefrontFacetCache.evictStore(storeId)` into product lifecycle events (activate, deactivate, delete) so the facet cache is kept consistent automatically.

---

---

## Commit 4 — Drop the Adapter DTO + Storefront Implementation

### Problem

After the first three commits the backend's `/api/stores/{slug}` endpoint still converted each `ProductCard` to a `StoreProductCardDto` (old field names: `productId`, `productName`, `mainImage`, `defaultVariantBasePrice`, `defaultVariantEffectivePrice`, etc.) before serializing the response. The Next.js storefront consumed those old names through a `StoreProductCard` TypeScript interface that didn't match the unified `ProductCard` / `CatalogProductCard` shape used everywhere else.

### Backend changes

**`StorePageResponse.java`**
- `List<StoreProductCardDto> products` → `List<ProductCard> products`

**`SellerStorePageService.java`**
- Removed the `toCardDto(ProductCard, UUID)` mapping method.
- `productCards` is now taken directly from `catalogPage.products().getContent()` — no field renaming, no image URL wrapping.

**`StoreProductCardDto.java`** — deleted.

**`SellerStorePageServiceTest.java`**
- Assertion updated: `.defaultVariantEffectivePrice()` → `.effectivePrice()`.
- Removed the now-unused `mediaUrlBuilder.buildUrlWithId(productImageId)` mock stub.

### Frontend changes (`storefront/`)

**`domains/store/types/store.types.ts`**
- Deleted `StoreProductCard` interface.
- Imports and re-exports `CatalogProductCard` from `@/shared/types/catalog-product.types`.
- `StorePageResponse.products` is now `CatalogProductCard[]`.

**`domains/store/api/storeApi.ts`**
- Product normalization updated to `CatalogProductCard` field names.

**`domains/store/utils/storePage.utils.ts`**
- All functions switched from `StoreProductCard` to `CatalogProductCard`.
- `product.productId` → `product.id` throughout.
- `product.hasActiveOffer` (pre-computed field) replaced by a local `hasActiveOffer(product)` helper that checks `discountAmount > 0 && (!offerEndsAt || offerEndsAt > now)`.

**`widgets/storefront/ProductCard.tsx`**
- Prop type changed from `StoreProductCard` to `CatalogProductCard`.
- New `sellerId: string` prop (extracted from the store context, not from the product).
- Field renames applied (see mapping below).
- `effectivePrice` and `activeOffer` computed locally from `basePrice`, `discountAmount`, and `offerEndsAt`.
- `resolvePrimaryBadge`, `resolveEyebrowLabel`, `resolveFooterLabel` helpers no longer take the full product — they receive only the derived booleans/counts they need.

**`widgets/storefront/ProductGrid.tsx`**
- `StoreProductCard[]` → `CatalogProductCard[]`.
- New `sellerId: string` prop forwarded to each `<ProductCard>`.
- `key={product.productId}` → `key={product.id}`.

**`app/store/[slug]/page.tsx`**
- Removed `StoreProductCard` import.
- `sellerId={store.sellerId}` passed to `<ProductGrid>` and `<StoreBestSellerRail>`.
- `StoreBestSellerRail` component updated to accept and forward `sellerId`.

### Field mapping — old → new

| `StoreProductCard` (deleted) | `CatalogProductCard` (unified) |
|---|---|
| `productId` | `id` |
| `productName` | `name` |
| `mainImage.url` | `mainImageUrl` |
| `defaultVariantBasePrice` | `basePrice` |
| `defaultVariantEffectivePrice` | `computeEffectivePrice(basePrice, discountAmount)` |
| `hasActiveOffer` | `discountAmount > 0 && (!offerEndsAt \|\| offerEndsAt > now)` |
| `defaultVariantId` | `variantId` |
| `sellerId` (on product) | `sellerId` (separate prop from store) |

---

## Architecture After All Four Changes

```
Storefront (buyer-facing)
  PublicProductController / PublicCollectionController
    └── StorefrontCatalogQueryService
          ├── StorefrontCatalogReadRepository  ──► storefront_product_cards (DB view)
          ├── ProductCardLookupService
          │     └── ProductCardCache (Caffeine, 15k entries, 32m TTL)
          │           └── ProductRepository.findCardsByIds()
          └── StorefrontFacetCache (Caffeine, per facet type, 5–10m TTL)
                └── StorefrontCatalogReadRepository

Store page (buyer-facing, per-store)
  PublicSellerStoreController  →  GET /api/stores/{slug}
    └── SellerStorePageService
          └── StorefrontCatalogQueryService   (same service as above)
          returns List<ProductCard> directly  (no adapter DTO)

Next.js storefront  →  /store/{slug}
  storeApi.ts  (fetchStorePage)
    └── CatalogProductCard[]   (shared type, matches ProductCard JSON)
  widgets/storefront/ProductCard.tsx
    └── sellerId comes from store.sellerId, not from the product card

Seller (management-facing)
  SellerProductController
    └── SellerCatalogQueryService
          └── SellerProductReadRepository  ──► seller_product_cards (DB view)

Cache invalidation
  ProductService (on activate/deactivate/delete)
    ├── ProductCardCache.invalidate(productId)
    └── StorefrontFacetCache.evictStore(storeId)
  StorePageCacheInvalidationService
    └── evicts full store_page_cache entries for affected store slugs
```

---

## Files Added

### Backend

| File | Notes |
|---|---|
| [ProductCard.java](src/main/java/com/bun/platform/catalog/product/product_dtos/ProductCard.java) | Unified storefront card record |
| [ProductCardCache.java](src/main/java/com/bun/platform/catalog/product/service/ProductCardCache.java) | Caffeine loading cache for product cards |
| [StorefrontCatalogReadRepository.java](src/main/java/com/bun/platform/catalog/product/repository/StorefrontCatalogReadRepository.java) | Native queries against `storefront_product_cards` |
| [StorefrontCatalogQueryService.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCatalogQueryService.java) | Storefront page orchestration |
| [StorefrontCatalogPage.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCatalogPage.java) | Page result record |
| [StorefrontCatalogQuery.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCatalogQuery.java) | Query params record |
| [StorefrontCatalogMetrics.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCatalogMetrics.java) | Metrics record |
| [StorefrontCategoryFacet.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCategoryFacet.java) | Category facet record |
| [StorefrontCollectionFacet.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontCollectionFacet.java) | Collection facet record |
| [StorefrontPriceBounds.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontPriceBounds.java) | Price bounds record |
| [StorefrontFacetCache.java](src/main/java/com/bun/platform/catalog/product/storefront/StorefrontFacetCache.java) | Facet + metrics Caffeine cache |
| [SellerProductCard.java](src/main/java/com/bun/platform/catalog/product/seller/SellerProductCard.java) | Seller-facing card record |
| [SellerProductCardProjection.java](src/main/java/com/bun/platform/catalog/product/seller/SellerProductCardProjection.java) | JDBC projection |
| [SellerCatalogQuery.java](src/main/java/com/bun/platform/catalog/product/seller/SellerCatalogQuery.java) | Seller query params record |
| [SellerCatalogQueryService.java](src/main/java/com/bun/platform/catalog/product/seller/SellerCatalogQueryService.java) | Seller catalog orchestration |
| [SellerProductReadRepository.java](src/main/java/com/bun/platform/catalog/product/repository/SellerProductReadRepository.java) | Native queries against `seller_product_cards` |
| [V11__storefront_product_cards_view.sql](src/main/resources/db/migration/V11__storefront_product_cards_view.sql) | DB views + indexes |

### Frontend (storefront/)

No new files were added — existing files were updated in place (see Files Modified below).

## Files Modified (Commit 4)

### Backend

| File | Change |
|---|---|
| [StorePageResponse.java](src/main/java/com/bun/platform/sellerstore/application/dto/StorePageResponse.java) | `products` field changed from `List<StoreProductCardDto>` to `List<ProductCard>` |
| [SellerStorePageService.java](src/main/java/com/bun/platform/sellerstore/application/SellerStorePageService.java) | Removed `toCardDto()` mapping; products taken directly from `catalogPage.products().getContent()` |
| [SellerStorePageServiceTest.java](src/test/java/com/bun/platform/sellerstore/application/SellerStorePageServiceTest.java) | Assertion updated to `effectivePrice()`; unused image mock stub removed |

### Frontend (storefront/)

| File | Change |
|---|---|
| [store.types.ts](storefront/src/domains/store/types/store.types.ts) | `StoreProductCard` deleted; `CatalogProductCard` imported from shared types; `StorePageResponse.products` is now `CatalogProductCard[]` |
| [storeApi.ts](storefront/src/domains/store/api/storeApi.ts) | Product normalization updated to `CatalogProductCard` field names |
| [storePage.utils.ts](storefront/src/domains/store/utils/storePage.utils.ts) | Switched to `CatalogProductCard`; `product.productId` → `product.id`; `hasActiveOffer` extracted as a local helper |
| [ProductCard.tsx](storefront/src/widgets/storefront/ProductCard.tsx) | Prop type changed to `CatalogProductCard`; new `sellerId: string` prop; all old field names updated; `effectivePrice` and `activeOffer` computed locally |
| [ProductGrid.tsx](storefront/src/widgets/storefront/ProductGrid.tsx) | Switched to `CatalogProductCard[]`; new `sellerId` prop forwarded to each card; `key` uses `product.id` |
| [page.tsx (store/\[slug\])](storefront/src/app/store/%5Bslug%5D/page.tsx) | Passes `store.sellerId` to `<ProductGrid>` and `<StoreBestSellerRail>`; `StoreProductCard` import removed |

## Files Deleted

| File | Replaced by |
|---|---|
| `ProductSearchCardView.java` | `ProductCard` |
| `StoreProductCardProjection.java` | `StorefrontCatalogReadRepository` projections |
| `StorePriceBoundsProjection.java` | `StorefrontPriceBoundsProjection` |
| `StoreCategoryFacetProjection.java` | `StorefrontCategoryFacetProjection` |
| `StoreCollectionFacetProjection.java` | `StorefrontCollectionFacetProjection` |
| `StoreSummaryProjection.java` | `StorefrontCatalogMetrics` |
| `StoreProductCardDto.java` | `ProductCard` (returned directly from `StorePageResponse`) |

Current branch note: `StorePageCacheInvalidationService.java` still exists. It handles full public store page cache invalidation, while `StorefrontFacetCache.evictStore()` handles storefront facet and metric cache invalidation.
