# Homepage UML

## Context And Boundaries

```mermaid
flowchart LR
    Frontend["Storefront root page\n/"] --> Api["GET /api/public/home"]
    Api --> HomeController["HomePageController"]
    HomeController --> HomeService["HomePageService"]

    HomeService --> CategoryDomain["Category domain"]
    HomeService --> ProductDomain["Product read path"]
    HomeService --> CollectionDomain["Collection read path"]
    HomeService --> HomepageCache["homepage cache"]

    ProductDomain --> ProductTables["product_definitions + variants"]
    CollectionDomain --> CollectionTables["product_collections + product_collection_items"]
    CategoryDomain --> CategoryTables["categories"]
```

## Class Diagram

```mermaid
classDiagram
    class HomePageController {
        +getHomePage(size)
    }

    class HomePageService {
        +getHomePageData(size)
        -loadFeaturedCollections()
        -buildSectionIndex()
        -buildSections()
        -buildProductSection()
        -buildCategorySection()
        -buildCollectionSection()
        -buildStaticSection()
        -buildHybridSection()
    }

    class HomePageCacheService {
        +evictHomePageCache()
    }

    class HomePageDataDto {
        +List categories
        +List products
        +List collections
        +List sections
    }

    class HomeCollectionSummaryDto {
        +Long id
        +String name
        +String slug
        +String description
        +String imageUrl
    }

    class HomeSectionDto {
        +String id
        +HomeSectionStrategy strategy
        +String title
        +String description
        +String ctaLabel
        +String ctaHref
        +List products
    }

    class HomeSectionStrategy {
        <<enum>>
        PRODUCT_BASED
        CATEGORY_BASED
        COLLECTION_BASED
        STATIC
        HYBRID
    }

    class ProductReadService {
        +getHomeProductIds(size)
        +getProductIdsForCategory(categoryId, size)
        +getProductCardMap(productIds)
        +getProductCardsByIds(productIds)
        +getProductCard(productId)
    }

    class CollectionService {
        +getCollectionProductIds(collectionId, page, size)
        +getCollectionProductCards(collectionId, page, size)
    }

    class CategoryService {
        +getAllRoots()
        +findCategoryWithAllChildrenIds(categoryId)
    }

    class ProductRepository {
        +findHomeProductIds(pageable)
        +findActiveProductIdsByCategoryIds(categoryIds, pageable)
        +findCardsByIds(productIds)
        +findCardById(productId)
    }

    class ProductCollectionRepository {
        +findByIsActiveTrueOrderByCreatedAtDesc(pageable)
    }

    class ProductEventListener {
        +handleProductCreated()
        +handleProductActivated()
        +handleProductDeactivated()
        +handleProductUpdated()
        +handleProductDeleted()
        +handleVariantCreated()
        +handleVariantActivated()
        +handleVariantDeactivated()
        +handleProductPriceChanged()
        +handleVariantPriceChanged()
    }

    class ProductCardProjection {
        +Long id
        +String name
        +String description
        +UUID mainImageId
        +String currency
        +Long variantId
        +BigDecimal basePrice
        +BigDecimal discountAmount
        +Instant offerEndsAt
        +String offerType
        +boolean hasRequiredAttributes
    }

    HomePageController --> HomePageService
    HomePageService --> CategoryService
    HomePageService --> ProductReadService
    HomePageService --> CollectionService
    HomePageService --> ProductCollectionRepository
    HomePageService --> HomePageDataDto
    HomePageDataDto --> HomeCollectionSummaryDto
    HomePageDataDto --> HomeSectionDto
    HomeSectionDto --> HomeSectionStrategy
    HomeSectionDto --> ProductCardProjection
    ProductReadService --> ProductRepository
    CollectionService --> ProductReadService
    ProductEventListener --> HomePageCacheService
```

## Homepage Read Sequence

```mermaid
sequenceDiagram
    actor Visitor
    participant Controller as HomePageController
    participant Service as HomePageService
    participant Cache as homepage
    participant CategoryService
    participant CollectionRepo as ProductCollectionRepository
    participant ProductRead as ProductReadService

    Visitor->>Controller: GET /api/public/home?size=8
    Controller->>Service: getHomePageData(8)

    alt homepage cache hit
        Service->>Cache: lookup(size key)
        Cache-->>Service: HomePageDataDto
    else homepage cache miss
        Service->>CategoryService: getAllRoots()
        CategoryService-->>Service: root categories
        Service->>CollectionRepo: findByIsActiveTrueOrderByCreatedAtDesc(page)
        CollectionRepo-->>Service: featured collections
        Service->>ProductRead: getHomeProductIds(size)
        ProductRead-->>Service: featured product IDs
        Service->>ProductRead: getProductIdsForCategory(...)
        ProductRead-->>Service: category product IDs
        Service->>ProductRead: getProductCardMap(allDistinctIds)
        ProductRead-->>Service: Map<Long, ProductCardProjection>
        Service->>Service: build sections from hydrated card map
        Service->>Cache: put(HomePageDataDto)
    end

    Service-->>Controller: HomePageDataDto
    Controller-->>Visitor: 200 OK + Cache-Control
```

## Batch Hydration Pipeline

```mermaid
flowchart TD
    A["Homepage wants multiple sections"] --> B["Collect IDs only"]
    B --> C["featured product IDs"]
    B --> D["category section IDs"]
    B --> E["collection section IDs"]
    C --> F["Union into ordered distinct set"]
    D --> F
    E --> F
    F --> G["ProductReadService.getProductCardMap(ids)"]
    G --> H{"product_card cache hit?"}
    H -- "Yes" --> I["reuse cached ProductCardProjection"]
    H -- "No" --> J["accumulate missing IDs"]
    J --> K["ProductRepository.findCardsByIds(missingIds)"]
    K --> L["write misses back to product_card"]
    I --> M["build ID -> card map"]
    L --> M
    M --> N["rebuild sections without extra repository reads"]
```

## Section Assembly Model

```mermaid
flowchart LR
    A["Root categories"] --> B["CATEGORY_BASED sections"]
    C["Featured products"] --> D["PRODUCT_BASED section"]
    E["Featured collections"] --> F["COLLECTION_BASED sections"]
    D --> G["STATIC section"]
    D --> H["HYBRID section"]
    B --> H
    F --> H
    B --> I["HomePageDataDto.sections"]
    D --> I
    F --> I
    G --> I
    H --> I
```

## Cache Layer Diagram

```mermaid
flowchart LR
    HomeReq["Homepage request"] --> HomeCache["homepage"]
    HomeCache --> HomeService["HomePageService"]

    HomeService --> CategoryCache["categorie_attributs"]
    HomeService --> CollectionCache["product_card_collections"]
    HomeService --> CardCache["product_card"]

    CollectionCache --> CollectionIds["ordered product IDs only"]
    CardCache --> ProductCards["ProductCardProjection"]
    HomeCache --> HomePayload["HomePageDataDto"]
```

## Invalidation Flow

```mermaid
flowchart TD
    ProductEvents["Product / Variant domain events"] --> ProductListener["ProductEventListener"]
    CollectionWrites["CollectionService mutations"] --> HomepageInvalidation["HomePageCacheService"]
    CategoryWrites["CategoryService mutations"] --> HomepageInvalidation

    ProductListener --> ProductCardEvict["evict product_card / product_cache when product-bound"]
    ProductListener --> HomepageInvalidation

    HomepageInvalidation --> HomeCache["homepage cache cleared"]
```

## Public Endpoint Cache Model

```mermaid
flowchart LR
    Client["Anonymous visitor"] --> Controller["HomePageController"]
    Controller --> Headers["Cache-Control: public, max-age=120"]
    Headers --> Edge["CDN / reverse proxy short reuse"]
    Controller --> Payload["HomePageDataDto"]
```

## Strategy State View

```mermaid
stateDiagram-v2
    [*] --> ProductBased
    ProductBased --> CategoryBased : root categories available
    CategoryBased --> CollectionBased : public collections available
    CollectionBased --> Static : derive editorial slice from featured products
    Static --> Hybrid : merge featured + category + collection
    Hybrid --> [*] : serialized into HomePageDataDto.sections
```

## Traffic-Oriented Read Model

```mermaid
flowchart TD
    A["Cold request"] --> B["homepage cache miss"]
    B --> C["batch ID collection"]
    C --> D["batch card hydration"]
    D --> E["assembled HomePageDataDto"]
    E --> F["homepage cache write"]

    G["Warm request"] --> H["homepage cache hit"]
    H --> I["return payload without rebuilding sections"]
```
