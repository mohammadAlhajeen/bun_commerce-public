# Category Domain Reference

## Overview

The `category` domain defines the catalog taxonomy and the attribute system used to describe products inside that taxonomy.

It is responsible for:

- maintaining the category tree
- marking categories as structural or sellable
- defining reusable product attributes
- storing predefined values for selectable attributes
- linking attributes to categories
- resolving inherited attributes from ancestor categories

This domain is implemented primarily in:

- `com.bun.platform.catalog.category`
- `com.bun.platform.catalog.category.service`
- `com.bun.platform.catalog.category.repository`
- `com.bun.platform.catalog.category.controller`

## Responsibilities

- model a hierarchical category tree with parent/child relationships
- expose public category-tree projections for browsing and navigation
- enforce a maximum hierarchy depth during category creation
- define global attribute definitions shared across the catalog
- store predefined attribute values when an attribute uses selectable options
- map attribute definitions to categories through `CategoryAttribute`
- resolve effective category attributes using parent traversal plus inheritance rules
- support soft deletion across categories, attributes, values, and junction mappings

## Package Summary

### `com.bun.platform.catalog.category`

Contains the core catalog-taxonomy model:

- `Category`
- `AttributeDefinition`
- `AttributeValue`
- `CategoryAttribute`

### `com.bun.platform.catalog.category.service`

Contains the application services:

- `CategoryService`
- `AttributeDefinitionService`

### `com.bun.platform.catalog.category.controller`

Contains the HTTP surface:

- `PublicCategoryController`
- `AdminCategoryController`

## Core Model

### `Category`

**Kind:** entity  
**Table:** `categories`

Represents one node in the catalog tree.

Key fields:

- `id`
- `name`
- `slug`
- `description`
- `parent`
- `children`
- `sellable`
- `products`
- `categoryAttributes`
- `deleted`
- `createdAt`
- `updatedAt`

Behavioral contract:

- `sellable = true` means products can be attached to the category
- `sellable = false` means the category is structural/navigation only
- `@PrePersist` auto-generates `slug` from `name` when slug is blank

Persistence notes:

- soft delete via `@SQLDelete`
- active-row filtering via `@SQLRestriction("deleted = false")`
- self-referencing FK `parent_id`
- migration defines cascade delete from parent to child at the DB level

### `AttributeDefinition`

**Kind:** entity  
**Table:** `attribute_definitions`

Global product attribute definition, shared across categories and products.

Key fields:

- `id`
- `name`
- `displayName`
- `optionType`
- `categorieAttributs`
- `attributeValues`
- `inherited`
- `deleted`
- `createdAt`
- `updatedAt`

Behavioral contract:

- `setName(...)` normalizes the stored name to lowercase trimmed text
- `addAttributeValue(...)` assigns the back-reference and appends the value
- `inherited = true` allows the attribute to flow from ancestor categories to descendants during lookup

`optionType` values come from `OptionType`:

- `FIXED`
- `FREE_INPUT`
- `SELECT`

Persistence notes:

- unique name across all attribute definitions
- soft delete enabled
- migration enforces `option_type` check constraint

### `AttributeValue`

**Kind:** entity  
**Table:** `attribute_values`

Predefined value option for an `AttributeDefinition`.

Key fields:

- `id`
- `name`
- `attributeDefinition`
- `deleted`
- `createdAt`
- `updatedAt`

Persistence notes:

- unique constraint on `(name, attribute_definition_id)`
- soft delete enabled
- used primarily with `SELECT`-style attributes, although the entity itself does not enforce that rule

### `CategoryAttribute`

**Kind:** entity  
**Table:** `category_attributes`

Junction entity linking categories to attribute definitions.

Key fields:

- `id`
- `inherited`
- `category`
- `attributeDefinition`
- `deleted`
- `createdAt`
- `updatedAt`

Persistence notes:

- unique constraint on `(category_id, attribute_definition_id)`
- soft delete enabled
- default `inherited = true`

Important implementation note:

- effective attribute inheritance during reads is controlled by `AttributeDefinition.inherited` in repository queries
- `CategoryAttribute.inherited` exists in the model and schema, but the current attribute-resolution queries do not use it as the deciding flag

## Services

### `CategoryService`

Owns category creation, update, deletion, and public tree retrieval.

Key operations:

- `findById(Long)`
- `create(CreateCategoryDTO)`
- `update(Long, UpdateCategoryDTO)`
- `delete(Long)`
- `getAllActiveCategories()`
- `getCategoryTree()`
- `getCategoryTreeById(Long)`
- `getCategoryTreeBySlug(String)`
- `getAllRoots()`
- `findCategoryWithAllChildrenIds(Long)`
- `findCategoryWithAllParentIds(Long)`

Important rules:

- slug must be unique
- when a parent is supplied during create, category depth may not exceed 5 levels
- deletion is soft delete
- parent traversal and child traversal are resolved with recursive CTE queries

Public tree behavior:

- root categories are returned by `getCategoryTree()`
- children are fetched through entity/projection mapping
- roots projection returns only `id`, `name`, `slug`

Implementation notes:

- `update(...)` checks slug uniqueness before loading the current category, so reusing the same existing slug on the same row can still trip the duplicate check
- `getCategoryTree()`, `getCategoryTreeById(...)`, and `getCategoryTreeBySlug(...)` currently fetch roots plus direct children; the comments mention conditional grandchildren, but the current JPQL does not implement that extra conditional join logic

### `AttributeDefinitionService`

Owns attribute-definition lifecycle and category linking.

Key operations:

- `create(CreateAttributeDefinition)`
- `update(UpdateAttributeDefinition)`
- `addAttributeValue(Long, CreateAttributeValue)`
- `setAttributeDefinitionCategory(Long, Long)`
- `findById(Long)`
- `findValuesByAttributeId(Long)`
- `findByCategoryId(Long)`
- `findValueByValueId(Long)`
- `findValueByValueIdAndAttId(Long, Long)`
- `findByCategoryIdAndAttributeId(Long, Long)`
- `findIdByCategoryIdAndAttributeId(Long, Long)`
- `findProjectionByCategoryId(Long)`
- `findValuesProjByAttributeId(Long)`
- `findAttributeProjByAttributeId(Long)`
- `findAttributeValuesProjByAttributeId(Long)`

Important rules:

- attribute definition name and display name must be unique on create
- duplicate value names inside one attribute definition are rejected
- a category cannot link the same effective attribute twice
- a category and its parent chain are capped at 50 effective attributes during linking
- effective attribute lookup is category-aware and ancestor-aware

Inheritance rule used for reads:

- direct category mappings are always included
- ancestor mappings are included only when the attribute definition itself has `inherited = true`

## DTO And Projection Surface

### Category DTOs

- `CreateCategoryDTO`
  - `name`
  - `slug`
  - `description`
  - `sellable`
  - `parentId`
- `UpdateCategoryDTO`
  - optional updates for the same fields

### Attribute DTOs

- `CreateAttributeDefinition`
  - `name`
  - `displayName`
  - `optionType`
  - optional initial `attributeValues`
- `UpdateAttributeDefinition`
  - `id`
  - optional `name`
  - optional `displayName`
  - optional `optionType`
  - optional `attributeValues`
  - optional `deleted`
- `CreateAttributeValue`
  - `name`

### Projections

- `CategoryTreeProjection`
  - `id`
  - `name`
  - `slug`
  - `sellable`
  - `children`
- `CategoryRootsProjection`
  - `id`
  - `name`
  - `slug`
- `getCategoryProjection`
  - `id`
  - `name`
  - `hasChildren`
- `AttributeDefinitionProjection`
  - `id`
  - `name`
  - `displayName`
  - `optionType`
- `AttributeValueProjection`
  - value-level projection for lightweight reads
- `AttributeWithValueDto`
  - attribute definition plus a set of `AttributeValueDto`

## Repository Surface

### `CategoryRepository`

Provides:

- minimal active-category projections
- root-only projections
- parent-child projections
- tree reads by root, id, or slug
- recursive parent ID expansion
- recursive child ID expansion
- depth calculation
- slug existence checks

Important details:

- recursive traversal is implemented with native CTEs
- tree methods filter on `deleted = false`

### `AttributeDefinitionRepository`

Provides:

- uniqueness checks
- entity graph loads with values
- projection reads
- attribute-value reads
- category-aware inherited attribute resolution

The central read query pattern is:

- gather category + ancestor IDs from `CategoryService`
- include direct category mappings always
- include ancestor mappings only when `AttributeDefinition.inherited = true`

### `CategoryAttributeRepository`

Simple persistence repository for the junction entity.

## HTTP Surface

### Public API

Base path: `/api/public/catalog`

Category endpoints:

- `GET /categories/tree`
- `GET /categories/tree/{slug}`
- `GET /categories/roots`

Attribute endpoints:

- `GET /categories/{categoryId}/attributes`
- `GET /attributes/{id}/values`
- `GET /attributes/{id}/with-values`

These endpoints return projections and DTOs rather than full mutable entities.

### Admin API

Base path: `/api/admin/catalog`

Authorization:

- class-level `@PreAuthorize("hasRole('ADMIN')")`

Category endpoints:

- `GET /categories/all`
- `POST /categories`
- `PUT /categories/{id}`
- `DELETE /categories/{id}`

Attribute endpoints:

- `POST /attributes`
- `PUT /attributes`
- `POST /attributes/{attributeId}/values`
- `POST /attributes/{attributeDefId}/link-category?categoryId=...`

## Exception Handling

### English

- Category and attribute errors should use the bilingual platform error envelope and should preserve enough structure for admin tools to distinguish validation, not-found, and taxonomy-conflict failures.
- `400 Bad Request`: use for malformed category or attribute payloads, invalid option or value combinations, or unsafe move or update input that fails validation before persistence.
- `404 Not Found`: use when the target category, attribute definition, attribute value, or linked reference does not exist.
- `409 Conflict`: use for duplicate slug or attribute names, maximum-depth violations, duplicate category-attribute links, excessive effective attributes, or state conflicts during delete or update operations.
- `403 Forbidden`: use when non-admin callers attempt to access admin mutation endpoints.
- `500 Internal Server Error`: reserve for unexpected recursive-query failures, persistence errors, or other runtime problems in taxonomy resolution.
- Current implementation note: this domain already mixes `EntityNotFoundException`, `IllegalArgumentException`, and `IllegalStateException`; the documented contract treats them as `404`, `400`, and `409` categories respectively.

### العربية

- يجب أن تستخدم أخطاء التصنيفات والسمات غلاف الأخطاء ثنائي اللغة مع بنية كافية تتيح لأدوات الإدارة التمييز بين أخطاء التحقق وعدم الوجود وتعارضات التصنيف.
- `400 طلب غير صحيح`: يستخدم عند وجود حمولة تصنيف أو سمة مشوهة، أو توليفات غير صالحة بين النوع والقيمة، أو مدخلات نقل أو تحديث غير آمنة تفشل في التحقق قبل الحفظ.
- `404 غير موجود`: يستخدم عندما لا يكون التصنيف أو تعريف السمة أو قيمة السمة أو المرجع المرتبط موجوداً.
- `409 تعارض`: يستخدم عند وجود تكرار في الـ slug أو أسماء السمات، أو تجاوز للعمق الأقصى، أو ربط مكرر بين التصنيف والسمة، أو عدد مفرط من السمات الفعالة، أو تعارض في حالة الحذف أو التحديث.
- `403 ممنوع`: يستخدم عندما يحاول غير المديرين الوصول إلى نقاط تعديل الإدارة.
- `500 خطأ داخلي في الخادم`: يحجز لفشل الاستعلامات الراجعة غير المتوقعة أو أخطاء التخزين أو أي مشكلة تشغيلية أخرى أثناء حل بنية التصنيف.
- ملاحظة تنفيذية حالية: هذا النطاق يمزج حالياً بين `EntityNotFoundException` و`IllegalArgumentException` و`IllegalStateException`، والعقد الموثق هنا يصنفها على الترتيب كفئات `404` و`400` و`409`.

## Persistence Summary

Migration `V3__catalog.sql` defines the category and attribute schema.

Primary tables for this domain:

- `categories`
- `attribute_definitions`
- `attribute_values`
- `category_attributes`

Downstream integration tables in the wider catalog:

- `product_definitions.category_id`
- `variant_attributes.attribute_id`
- `variant_attribute_selection.attribute_value_id`

Key constraints:

- unique `categories.name`
- unique `categories.slug`
- unique `attribute_definitions.name`
- unique `(attribute_values.name, attribute_definition_id)`
- unique `(category_id, attribute_definition_id)` in `category_attributes`

Soft-delete coverage:

- `categories`
- `attribute_definitions`
- `attribute_values`
- `category_attributes`

## End-to-End Flows

### Create Category

1. Admin posts `CreateCategoryDTO`
2. Service verifies slug uniqueness
3. If parent exists, repository computes the parent depth
4. Depth above 5 is rejected
5. Category is saved
6. Cache entries under `categorie_attributs` are evicted

### Link Attribute To Category

1. Admin selects an attribute definition and a category
2. Service loads effective attributes for the category and its parent chain
3. Duplicate effective link is rejected
4. Effective attribute count above 50 is rejected
5. `CategoryAttribute` row is inserted
6. Future reads for that category resolve the attribute directly or via inheritance

### Resolve Effective Attributes For A Category

1. Service loads category and all ancestor IDs using recursive CTE
2. Repository selects attribute definitions mapped to any of those categories
3. Direct category mappings are always returned
4. Ancestor mappings are returned only when `AttributeDefinition.inherited = true`
5. Response is returned as entities or projections depending on caller

### Public Category Browsing

1. Client fetches root categories or the category tree
2. UI navigates by slug or category ID
3. UI fetches effective attribute projections for the selected category
4. UI fetches value projections for selectable attributes as needed

## Design Constraints And Observations

- Categories are both navigational and business-semantic through the `sellable` flag
- The attribute system is global, not per-product, which keeps attribute semantics consistent across the catalog
- Effective attribute inheritance is ancestor-based and query-driven rather than computed in service code
- Soft deletion is pervasive and built into the ORM mappings
- The current implementation documents conditional-grandchildren tree loading, but the active queries do not fully implement that behavior
- Slug uniqueness validation in updates is stricter than ideal and can reject unchanged slugs

## Improvement Areas

- Align the tree-query implementation with its documentation, or simplify the documentation if grandchildren are intentionally not loaded.
- Fix slug uniqueness checks during update so unchanged slugs on the same category are allowed.
- Clarify inheritance semantics by using one authoritative flag. Right now `CategoryAttribute.inherited` exists, but effective reads depend on `AttributeDefinition.inherited`.
- Add stronger validation around category moves and updates to avoid circular parent relationships and unsafe taxonomy edits.
- Add explicit tests for recursive parent/child resolution, inheritance, soft deletion, and maximum-depth enforcement.
