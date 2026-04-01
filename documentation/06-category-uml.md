# Category UML

## Class Diagram

```mermaid
classDiagram
    class Category {
        +Long id
        +String name
        +String slug
        +String description
        +boolean sellable
        +boolean deleted
        +Instant createdAt
        +Instant updatedAt
        +onCreate()
    }

    class AttributeDefinition {
        +Long id
        +String name
        +String displayName
        +OptionType optionType
        +boolean inherited
        +boolean deleted
        +Instant createdAt
        +Instant updatedAt
        +setName(name)
        +addAttributeValue(value)
    }

    class AttributeValue {
        +Long id
        +String name
        +boolean deleted
        +Instant createdAt
        +Instant updatedAt
    }

    class CategoryAttribute {
        +Long id
        +boolean inherited
        +boolean deleted
        +Instant createdAt
        +Instant updatedAt
    }

    class OptionType {
        <<enumeration>>
        FIXED
        FREE_INPUT
        SELECT
    }

    Category "0..1" --> "0..*" Category : parent/children
    Category "1" --> "0..*" CategoryAttribute : attribute mappings
    AttributeDefinition "1" --> "0..*" CategoryAttribute : mapped by
    AttributeDefinition "1" --> "0..*" AttributeValue : predefined values
    AttributeDefinition --> OptionType
```

## Service Dependency Diagram

```mermaid
flowchart LR
    PublicCategoryController["PublicCategoryController"] --> CategoryService["CategoryService"]
    PublicCategoryController --> AttributeDefinitionService["AttributeDefinitionService"]

    AdminCategoryController["AdminCategoryController"] --> CategoryService
    AdminCategoryController --> AttributeDefinitionService

    CategoryService --> CategoryRepository["CategoryRepository"]

    AttributeDefinitionService --> AttributeDefinitionFactory["AttributeDefinitionFactory"]
    AttributeDefinitionService --> AttributeDefinitionRepository["AttributeDefinitionRepository"]
    AttributeDefinitionService --> CategoryService
    AttributeDefinitionService --> CategoryAttributeRepository["CategoryAttributeRepository"]
```

## Category Creation Sequence

```mermaid
sequenceDiagram
    participant Admin
    participant AdminCategoryController
    participant CategoryService
    participant CategoryRepository

    Admin->>AdminCategoryController: POST /api/admin/catalog/categories
    AdminCategoryController->>CategoryService: create(dto)
    CategoryService->>CategoryRepository: existsBySlug(dto.slug)
    CategoryRepository-->>CategoryService: false
    alt parentId provided
        CategoryService->>CategoryRepository: findCategoryDepth(parentId)
        CategoryRepository-->>CategoryService: depth
        CategoryService->>CategoryRepository: findById(parentId)
        CategoryRepository-->>CategoryService: parent
    end
    CategoryService->>CategoryRepository: save(category)
    CategoryRepository-->>CategoryService: saved category
    CategoryService-->>AdminCategoryController: Category
    AdminCategoryController-->>Admin: 201 Created
```

## Effective Attribute Resolution Sequence

```mermaid
sequenceDiagram
    participant Client
    participant PublicCategoryController
    participant AttributeDefinitionService
    participant CategoryService
    participant CategoryRepository
    participant AttributeDefinitionRepository

    Client->>PublicCategoryController: GET /categories/{categoryId}/attributes
    PublicCategoryController->>AttributeDefinitionService: findProjectionByCategoryId(categoryId)
    AttributeDefinitionService->>CategoryService: findCategoryWithAllParentIds(categoryId)
    CategoryService->>CategoryRepository: findCategoryWithAllParentIds(categoryId)
    CategoryRepository-->>CategoryService: category + ancestor ids
    CategoryService-->>AttributeDefinitionService: ids
    AttributeDefinitionService->>AttributeDefinitionRepository: findAttProjByCategoryId(ids, categoryId)
    AttributeDefinitionRepository-->>AttributeDefinitionService: effective attributes
    AttributeDefinitionService-->>PublicCategoryController: AttributeDefinitionProjection[]
    PublicCategoryController-->>Client: 200 OK
```

## Link Attribute To Category Sequence

```mermaid
sequenceDiagram
    participant Admin
    participant AdminCategoryController
    participant AttributeDefinitionService
    participant CategoryService
    participant AttributeDefinitionRepository
    participant CategoryAttributeRepository

    Admin->>AdminCategoryController: POST /attributes/{attributeDefId}/link-category?categoryId=...
    AdminCategoryController->>AttributeDefinitionService: setAttributeDefinitionCategory(attributeDefId, categoryId)
    AttributeDefinitionService->>AttributeDefinitionRepository: findById(attributeDefId)
    AttributeDefinitionService->>CategoryService: findById(categoryId)
    AttributeDefinitionService->>AttributeDefinitionService: findByCategoryId(categoryId)
    alt duplicate or too many attributes
        AttributeDefinitionService-->>AdminCategoryController: IllegalStateException
    else valid link
        AttributeDefinitionService->>CategoryAttributeRepository: save(CategoryAttribute)
        AttributeDefinitionService-->>AdminCategoryController: void
        AdminCategoryController-->>Admin: 204 No Content
    end
```

## State Diagram For Category Node Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Structural : create with sellable=false
    Draft --> Sellable : create with sellable=true
    Structural --> Sellable : update sellable=true
    Sellable --> Structural : update sellable=false
    Structural --> Deleted : soft delete
    Sellable --> Deleted : soft delete
```

## ER View

```mermaid
flowchart LR
    categories["categories"]
    attribute_definitions["attribute_definitions"]
    attribute_values["attribute_values"]
    category_attributes["category_attributes"]
    product_definitions["product_definitions"]
    variant_attributes["variant_attributes"]
    variant_attribute_selection["variant_attribute_selection"]

    categories --> categories
    categories --> category_attributes
    attribute_definitions --> category_attributes
    attribute_definitions --> attribute_values
    categories --> product_definitions
    attribute_definitions --> variant_attributes
    attribute_values --> variant_attribute_selection
```
