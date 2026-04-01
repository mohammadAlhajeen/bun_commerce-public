# Product UML

## Class Diagram

```mermaid
classDiagram
    class ProductDefinition {
        +Long id
        +String name
        +String description
        +Currency currency
        +FulfillmentTime fulfillmentTime
        +Boolean isActive
        +Double averageRating
        +int salesCount
        +Long sellerId
        +InventoryPolicy inventoryPolicy
        +UUID mainImageId
        +Long version
        +Instant createdAt
        +Instant updatedAt
    }

    class Variant {
        +Long id
        +String name
        +VariantPrice price
        +String sku
        +boolean isActive
        +int salesCount
        +int maxOrderQuantity
        +boolean isDefault
        +Long version
        +setActive(active)
        +setDefault(defaultFlag)
        +validateOrderQuantity(qty)
    }

    class Inventory {
        +Long variantId
        +int qtyOnHand
        +int qtyReserved
        +Instant updatedAt
        +getAvailable()
        +reserve(qty)
        +release(qty)
        +commit(qty)
    }

    class VariantPrice {
        +BigDecimal basePrice
        +BigDecimal discountAmount
        +Long activeOfferId
        +Instant offerEndsAt
    }

    class VariantAttribute {
        +Long id
        +String name
        +Long attributeId
        +Boolean isRequired
        +boolean isActive
        +OptionType optionType
    }

    class VariantAttributeSelection {
        +Long id
        +String name
        +UUID mediaItemId
        +Integer sortOrder
        +boolean isActive
        +boolean isDefault
        +Long attributeValueId
    }

    class VariantMedia {
        +Long id
        +UUID mediaItemId
        +boolean mainMedia
        +Integer sortOrder
    }

    class Tag {
        +Long id
        +String name
    }

    class ProductCollection {
        +Long id
        +String name
        +String slug
        +String description
        +Long sellerId
        +Boolean isActive
        +boolean deleted
        +UUID mediaItemId
    }

    class ProductCollectionItem {
        +Long id
        +Integer sortOrder
        +Instant createdAt
        +Instant updatedAt
    }

    class Category {
        <<external catalog>>
    }

    ProductDefinition "1" --> "1" Category : belongs to
    ProductDefinition "1" --> "1..*" Variant : owns
    Variant "1" --> "0..1" Inventory : tracked stock
    Variant "1" --> "1" VariantPrice : embeds
    Variant "1" --> "0..*" VariantAttribute : owns
    VariantAttribute "1" --> "0..*" VariantAttributeSelection : owns
    Variant "1" --> "0..*" VariantMedia : owns
    ProductDefinition "0..*" --> "0..*" Tag : tagged by
    ProductCollection "1" --> "0..*" ProductCollectionItem : owns
    ProductDefinition "1" --> "0..*" ProductCollectionItem : appears in
```

## Service Dependency Diagram

```mermaid
flowchart LR
    SellerProductController["SellerProductController"] --> ProductService["ProductService"]
    SellerProductController --> ProductVariantService["ProductVariantService"]
    SellerProductController --> ProductReadService["ProductReadService"]
    SellerVariantController["SellerVariantController"] --> ProductVariantService

    PublicProductController["PublicProductController"] --> ProductViewService["ProductViewService"]
    PublicProductController --> ProductReadService

    PublicCollectionController["PublicCollectionController"] --> CollectionService["CollectionService"]

    ProductService --> ProductRepository["ProductRepository"]
    ProductService --> CategoryService["CategoryService"]
    ProductService --> VariantService["VariantService"]
    ProductService --> CatalogeMediaService["CatalogeMediaService"]
    ProductService --> TagService["TagService"]
    ProductService --> ProductVariantService
    ProductService --> InventoryService["InventoryService"]
    ProductService --> DomainEventPublisher["DomainEventPublisher"]

    VariantService --> VariantAttributeService["VariantAttributeService"]
    VariantService --> CatalogeMediaService
    VariantService --> VariantRepository["VariantRepository"]
    VariantService --> ProductRepository

    ProductVariantService --> ProductRepository
    ProductVariantService --> VariantRepository
    ProductVariantService --> VariantService
    ProductVariantService --> InventoryService
    ProductVariantService --> OfferReassignmentService["OfferReassignmentService"]
    ProductVariantService --> DomainEventPublisher

    InventoryService --> InventoryRepository["InventoryRepository"]

    ProductReadService --> ProductRepository
    ProductReadService --> VariantRepository
    ProductReadService --> ProductResponseMapper["ProductResponseMapper"]
    ProductReadService --> DomainEventPublisher

    ProductViewService --> ProductReadService
    ProductViewService --> DomainEventPublisher

    CollectionService --> ProductCollectionRepository["ProductCollectionRepository"]
    CollectionService --> ProductCollectionItemRepository["ProductCollectionItemRepository"]
    CollectionService --> ProductCacheService["ProductCacheService"]
    CollectionService --> ProductRepository
    CollectionService --> ProductReadService

    ProductCacheService --> CacheManager["CacheManager"]
    ProductCacheService --> ProductCollectionRepository
    ProductCacheService --> VariantService
```

## Product Creation Sequence

```mermaid
sequenceDiagram
    actor Seller
    participant SellerProductController
    participant UserIdentityService
    participant ProductService
    participant CategoryService
    participant TagService
    participant VariantService
    participant VariantAttributeService
    participant CatalogeMediaService
    participant ProductRepository
    participant InventoryService
    participant DomainEventPublisher

    Seller->>SellerProductController: POST /api/seller/products
    SellerProductController->>UserIdentityService: extractUserIdFromJwt(jwt)
    UserIdentityService-->>SellerProductController: sellerId
    SellerProductController->>ProductService: createProduct(sellerId, dto)
    Note over SellerProductController,ProductService: Controller contract = tolerant draft creation
    ProductService->>CategoryService: findById(dto.categoryId)
    CategoryService-->>ProductService: Category
    ProductService->>ProductService: validate category is sellable
    opt dto.tags exists
        ProductService->>TagService: processAndFetchTags(tags)
        Note over TagService: trim + lowercase + deduplicate + upsert
        TagService-->>ProductService: Tag list
    end
    loop each variant dto
        ProductService->>VariantService: createVariant(variantDto, product, sellerId)
        VariantService->>CatalogeMediaService: handleMediaItems(...)
        Note over CatalogeMediaService: invalid seller media ignored
        opt attributes exist
            VariantService->>VariantAttributeService: createVariantAttributes(...)
            Note over VariantAttributeService: invalid values tolerated,\nextra defaults ignored
            VariantAttributeService-->>VariantService: VariantAttribute list
        end
        VariantService-->>ProductService: Variant
    end
    ProductService->>ProductService: assign first active default or fallback to first variant
    ProductService->>CatalogeMediaService: fetchValidMediaIdForSeller(mainImageId, sellerId)
    Note over ProductService,CatalogeMediaService: fallback to default variant main media when request main image is invalid or missing
    ProductService->>ProductRepository: save(product)
    ProductRepository-->>ProductService: ProductDefinition
    opt inventoryPolicy == TRACKED
        loop each saved variant
            ProductService->>InventoryService: createInitialInventory(variantId, initialStock)
        end
    end
    ProductService->>DomainEventPublisher: publish(ProductCreatedEvent)
    ProductService-->>SellerProductController: ProductDefinition
    SellerProductController-->>Seller: 201 Created
```

## Create Product Activity Diagram

```mermaid
flowchart TD
    A["POST /api/seller/products"] --> B["Extract sellerId from JWT"]
    B --> C["Validate request body"]
    C --> D{"variantsDto empty?"}
    D -- "Yes" --> X["Fail: Product must have at least one variant"]
    D -- "No" --> E["Load category"]
    E --> F{"Category sellable?"}
    F -- "No" --> Y["Fail: category not sellable"]
    F -- "Yes" --> G["Build ProductDefinition"]
    G --> H["Normalize and attach tags"]
    H --> I["Create variants"]
    I --> J["Sanitize media and attributes"]
    J --> K["Choose default variant"]
    K --> L["Resolve main image"]
    L --> M["Persist ProductDefinition"]
    M --> N["Initialize tracked inventories"]
    N --> O["Publish ProductCreatedEvent"]
    O --> P["Return 201 Created"]
```

## Tolerant Creation Rules

```mermaid
flowchart LR
    A["Input issue"] --> B{"Critical?"}
    B -- "Yes" --> C["Reject request"]
    B -- "No" --> D["Sanitize / ignore / normalize"]
    C --> E["400 response"]
    D --> F["Continue product creation"]

    G["Missing variants"] --> C
    H["Non-sellable category"] --> C
    I["Invalid media reference"] --> D
    J["Duplicate tag"] --> D
    K["Conflicting attribute option type"] --> D
    L["Multiple default selections"] --> D
    M["Unknown attribute value"] --> D
```

## Variant Lifecycle Sequence

```mermaid
sequenceDiagram
    actor Seller
    participant SellerProductController
    participant ProductVariantService
    participant ProductRepository
    participant VariantRepository
    participant VariantService
    participant OfferReassignmentService
    participant DomainEventPublisher

    Seller->>SellerProductController: PATCH variant endpoint
    SellerProductController->>ProductVariantService: operation(productId, variantId, sellerId, ...)
    ProductVariantService->>ProductRepository: findByIdAndSellerId(productId, sellerId)
    ProductRepository-->>ProductVariantService: ProductDefinition

    alt change default
        ProductVariantService->>ProductVariantService: reassignDefaultVariant(...)
        ProductVariantService->>DomainEventPublisher: publish(DefaultVariantChangedEvent)
    else deactivate
        ProductVariantService->>ProductVariantService: ensure one active variant remains
        ProductVariantService->>DomainEventPublisher: publish(VariantDeactivatedEvent)
    else activate
        ProductVariantService->>ProductVariantService: activate variant
        ProductVariantService->>DomainEventPublisher: publish(VariantActivatedEvent)
    else update price
        ProductVariantService->>VariantRepository: save(variant)
        opt active offer exists
            ProductVariantService->>OfferReassignmentService: applyDiscountByOfferId(...)
        end
        ProductVariantService->>DomainEventPublisher: publish(VariantPriceChangedEvent)
    end

    ProductVariantService-->>SellerProductController: updated product or variant
    SellerProductController-->>Seller: 200 OK
```

## Inventory Reservation Rules

```mermaid
flowchart LR
    A["qtyOnHand"] --> D["available = qtyOnHand - qtyReserved"]
    B["qtyReserved"] --> D

    D --> E{"Operation"}
    E -- "reserve(qty)" --> F["Increase qtyReserved"]
    E -- "release(qty)" --> G["Decrease qtyReserved"]
    E -- "commit(qty)" --> H["Decrease qtyReserved and qtyOnHand"]

    F --> I["Reject if qty <= 0 or qty > available"]
    G --> J["Reject if qty <= 0 or qty > qtyReserved"]
    H --> K["Reject if qty <= 0 or qty > qtyReserved"]
```

## Public Product Read Sequence

```mermaid
sequenceDiagram
    actor Visitor
    participant PublicProductController
    participant ProductViewService
    participant ProductReadService
    participant ProductRepository
    participant VariantRepository
    participant DomainEventPublisher

    Visitor->>PublicProductController: GET /api/public/products/{id}
    PublicProductController->>ProductViewService: getActiveProduct(id, null)
    ProductViewService->>ProductReadService: getActiveProduct(id)
    ProductReadService->>ProductRepository: findByIdAndIsActiveTrue(id)
    ProductRepository-->>ProductReadService: ProductDefinition
    ProductReadService->>VariantRepository: findActiveVariantsByProductId(id)
    VariantRepository-->>ProductReadService: active variants
    ProductReadService-->>ProductViewService: ProductWithVarsResponseDto
    ProductViewService->>DomainEventPublisher: publish(ProductViewedEvent)
    ProductViewService-->>PublicProductController: ProductWithVarsResponseDto
    PublicProductController-->>Visitor: 200 OK
```

## Collection Rendering Sequence

```mermaid
sequenceDiagram
    actor Visitor
    participant PublicCollectionController
    participant CollectionService
    participant ProductCacheService
    participant ProductReadService

    Visitor->>PublicCollectionController: GET /api/public/collections/{id}/products?page=&size=
    PublicCollectionController->>CollectionService: getCollectionProductCards(id, page, size)
    CollectionService->>ProductCacheService: getCollectionProductIds(id, page, size)
    ProductCacheService-->>CollectionService: List<Long> productIds
    loop each productId
        CollectionService->>ProductReadService: getProductCard(productId)
        ProductReadService-->>CollectionService: ProductCardProjection
    end
    CollectionService-->>PublicCollectionController: List<ProductCardProjection>
    PublicCollectionController-->>Visitor: 200 OK
```

## Product State Diagram

```mermaid
stateDiagram-v2
    [*] --> DraftLike
    DraftLike --> Active : createProduct(isActive=true)
    DraftLike --> Inactive : createProduct(isActive=false)
    Active --> Inactive : setProductActive(false)
    Inactive --> Active : setProductActive(true)
    Active --> Deleted : deleteProduct()
    Inactive --> Deleted : deleteProduct()
```

## Variant Invariant Diagram

```mermaid
flowchart LR
    A["Variant requested"] --> B{"Active?"}
    B -- "No" --> C["Cannot be default"]
    B -- "Yes" --> D{"Default?"}
    D -- "Yes" --> E["Valid default variant"]
    D -- "No" --> F["Regular active variant"]
    E --> G["Product must still have at least one active variant"]
    F --> G
    C --> G
```
