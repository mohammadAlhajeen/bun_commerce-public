# Seller Store UML

## Context And Boundaries

```mermaid
flowchart LR
    SellerProfile["Legacy store profile write model\ncom.bun.platform.store"] --> StoreRow["stores table"]
    ProductDomain["Product domain\nProductDefinition + default Variant"] --> ProductTables["product_definitions + variants"]
    SellerStore["Seller Store read module\ncom.bun.platform.sellerstore"] --> StoreRow
    SellerStore --> ProductTables
    SellerStore --> Cache["store_page_cache"]
    PublicApi["GET /api/stores/{slug}"] --> SellerStore
    Frontend["/store/{slug} page"] --> PublicApi
```

## Class Diagram

```mermaid
classDiagram
    class Store {
        +Long id
        +Long sellerId
        +String storeName
        +String slug
        +String description
        +UUID logoImageId
        +UUID bannerImageId
        +boolean isActive
        +String themeCode
        +Instant createdAt
        +Instant updatedAt
    }

    class SellerStore {
        +Long storeId
        +Long sellerId
        +String storeName
        +StoreSlug slug
        +String description
        +UUID logoImageId
        +UUID bannerImageId
        +boolean active
        +Instant createdAt
        +StoreTheme theme
        +long totalProducts
        +long activeOfferProductCount
    }

    class StoreSlug {
        +String value
        +of()
        +slugify()
        +publicPath()
    }

    class StoreTheme {
        +String code
        +of()
    }

    class StorePageFilter {
        +Long categoryId
        +BigDecimal minPrice
        +BigDecimal maxPrice
        +String keyword
        +normalized()
    }

    class StoreSummaryDto {
        +Long storeId
        +Long sellerId
        +String storeName
        +String slug
        +String publicPath
        +String description
        +MediaUrlWithId logoImage
        +MediaUrlWithId bannerImage
        +boolean active
        +Instant createdAt
        +String themeCode
        +long totalProducts
        +long activeOfferProductCount
    }

    class StoreProductCardDto {
        +Long productId
        +String productName
        +MediaUrlWithId mainImage
        +BigDecimal defaultVariantEffectivePrice
        +boolean hasActiveOffer
        +Long sellerId
        +boolean featured
    }

    class StorePageResponse {
        +StoreSummaryDto store
        +List products
        +StoreAvailableFiltersDto filters
        +StoreAppliedFiltersDto appliedFilters
        +StorePaginationDto pagination
    }

    class SellerStorePageService {
        +getStorePage()
    }

    class StorePageReadRepository {
        +findStoreSummaryBySlug()
        +findStoreProductCards()
        +findAvailableCategories()
        +findPriceBounds()
        +findSlugBySellerId()
        +findSlugByProductId()
        +findSlugByVariantId()
    }

    class StorePageCacheKeyFactory {
        +build()
    }

    class StorePageCacheInvalidationService {
        +evictBySellerId()
        +evictByProductId()
        +evictByVariantId()
        +evictBySlug()
    }

    class PublicSellerStoreController {
        +getStoreBySlug()
    }

    class ProductDefinition {
        +Long id
        +Long sellerId
        +String name
        +UUID mainImageId
        +Boolean isActive
        +Category category
    }

    class Variant {
        +Long id
        +boolean isDefault
        +boolean isActive
        +VariantPrice price
    }

    class VariantPrice {
        +BigDecimal basePrice
        +BigDecimal discountAmount
        +Long activeOfferId
        +Instant offerEndsAt
    }

    PublicSellerStoreController --> SellerStorePageService
    SellerStorePageService --> StorePageReadRepository
    SellerStorePageService --> StorePageCacheKeyFactory
    SellerStorePageService --> StoreSummaryDto
    SellerStorePageService --> StoreProductCardDto
    SellerStorePageService --> StorePageResponse
    SellerStore --> StoreSlug
    SellerStore --> StoreTheme
    ProductDefinition "1" --> "1..*" Variant : owns
    Variant --> VariantPrice
    Store "1" --> "1" SellerStore : projected as
```

## Store Page Read Sequence

```mermaid
sequenceDiagram
    actor Visitor
    participant Controller as PublicSellerStoreController
    participant Service as SellerStorePageService
    participant CacheKey as StorePageCacheKeyFactory
    participant Repo as StorePageReadRepository
    participant Cache as store_page_cache

    Visitor->>Controller: GET /api/stores/{slug}?page=&size=&filters
    Controller->>Service: getStorePage(slug, filter, pageable)
    Service->>CacheKey: build(slug, filter, pageable)
    CacheKey-->>Service: cache key

    alt cache hit
        Service->>Cache: lookup(key)
        Cache-->>Service: StorePageResponse
    else cache miss
        Service->>Repo: findStoreSummaryBySlug(slug)
        Repo-->>Service: StoreSummaryProjection
        Service->>Repo: findStoreProductCards
        Repo-->>Service: paged product card projections
        Service->>Repo: findAvailableCategories(slug)
        Repo-->>Service: category facet projections
        Service->>Repo: findPriceBounds(slug)
        Repo-->>Service: StorePriceBoundsProjection
        Service->>Cache: put(key, response)
    end

    Service-->>Controller: StorePageResponse
    Controller-->>Visitor: 200 OK
```

## Product Card Query Pipeline

```mermaid
flowchart TD
    A["stores.slug"] --> B["resolve seller scope"]
    B --> C["join active product_definitions"]
    C --> D["join active default variants only"]
    D --> E["compute effective price from VariantPrice"]
    E --> F["apply optional category filter"]
    F --> G["apply keyword filter against product/category/tags"]
    G --> H["apply min/max effective price filter"]
    H --> I["mark featured products"]
    I --> J["order by featured, sort_order, createdAt, productId"]
    J --> K["return paged product card projection"]
```

## Cache Invalidation Flow

```mermaid
flowchart LR
    ProductEvents["Product / Variant domain events"] --> Listener["StorePageCacheInvalidationListener"]
    StoreWrites["StoreService writes"] --> Invalidation["StorePageCacheInvalidationService"]
    Listener --> Invalidation
    Invalidation --> Lookup["StorePageReadRepository slug lookup"]
    Lookup --> Prefix["store:{slug}:* prefix"]
    Prefix --> Cache["store_page_cache entries removed"]
```

## Price SSOT Diagram

```mermaid
flowchart LR
    Product["ProductDefinition"] -->|"no price field used"| Card["Store product card"]
    Variant["Default Variant"] --> VariantPrice["basePrice + discountAmount + activeOfferId + offerEndsAt"]
    VariantPrice --> Effective["effectivePrice projection"]
    Effective --> Card
```

## Filtering Model

```mermaid
flowchart LR
    Request["StorePageFilter"] --> Category["categoryId"]
    Request --> Price["minPrice / maxPrice"]
    Request --> Keyword["keyword"]

    Category --> Query["findStoreProductCards"]
    Price --> Query
    Keyword --> Query

    Query --> Page["paged product cards"]
    Query --> Summary["store-scoped filter bounds remain separate"]
```

## Store Profile State

```mermaid
stateDiagram-v2
    [*] --> Active : store row exists and is_active=true
    Active --> Inactive : store profile disabled
    Inactive --> Active : store profile re-enabled
    Inactive --> [*] : hidden from public store page
```

## Future Extension View

```mermaid
flowchart TD
    A["Current seller store page"] --> B["Theme code only"]
    A --> C["Featured product table"]
    A --> D["Active-offer product count"]

    B --> E["Future theme registry / templates"]
    C --> F["Seller-facing featured-product management"]
    D --> G["Future aggregated store-level merchandising widgets"]
```
