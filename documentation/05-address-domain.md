# Address Domain Reference

## Overview

The `address` domain owns the normalized geographic hierarchy used across the platform:

- `Country`
- `State`
- `City`
- `Street`
- `Address`

It also provides the read and write APIs used to browse location data, manage the reusable base-address catalog, and support user-specific address assignment through the `app_user_address` junction managed from the app-user domain.

This domain is implemented primarily in:

- `com.bun.platform.address`
- `com.bun.platform.address.service`
- `com.bun.platform.address.repository`
- `com.bun.platform.address.controller`

## Responsibilities

- model the geographic hierarchy `Country -> State -> City -> Street -> Address`
- store optional polygon and centroid geometry for states and cities using PostGIS
- expose public read APIs for country, state, city, street, and address lookup
- expose admin APIs for maintaining the hierarchy
- support flat and hierarchical address projections for downstream consumers
- provide reusable base addresses that can be linked to users, orders, shipments, and seller profiles
- coordinate geo-import of state and city shapes through Python scripts

## Package Summary

### `com.bun.platform.address`

Contains the domain entities and the `AddressRepository`.

Primary entities:

- `Country`
- `State`
- `City`
- `Street`
- `Address`

### `com.bun.platform.address.service`

Contains the application services:

- `CountryService`
- `StateService`
- `CityService`
- `StreetService`
- `AddressService`
- `StateGeoImportService`
- `CityGeoImportService`

### `com.bun.platform.address.controller`

Contains the HTTP surface:

- `PublicAddressController`
- `AdminAddressController`

## Core Model

### `Country`

**Kind:** entity  
**Table:** `countries`

Top-level geographic unit.

Key fields:

- `id`
- `name`
- `code`: ISO-style two-character code
- `phoneCode`
- `states`
- `createdAt`
- `updatedAt`

Persistence notes:

- `name` is unique
- `code` is unique when present
- one country owns many states

### `State`

**Kind:** entity  
**Table:** `states`

Second-level geographic unit belonging to a country.

Key fields:

- `id`
- `name`
- `country`
- `geom`: `Polygon` boundary in SRID 4326
- `centroid`: `Point` in SRID 4326
- `cities`
- `createdAt`
- `updatedAt`

Behavioral contract:

- `setLocation(latitude, longitude)` updates the centroid point

Persistence notes:

- FK to `countries`
- geometry columns use PostGIS
- migration defines cascade delete from country to state

### `City`

**Kind:** entity  
**Table:** `cities`

Third-level geographic unit belonging to a state.

Key fields:

- `id`
- `name`
- `state`
- `geom`: `Polygon` boundary in SRID 4326
- `centroid`: `Point` in SRID 4326
- `streets`
- `createdAt`
- `updatedAt`

Behavioral contract:

- `setLocation(latitude, longitude)` updates the centroid point
- `hasLocation()` indicates whether centroid exists
- `distanceTo(City)` estimates distance in kilometers using centroid geometry

Persistence notes:

- unique constraint on `(name, state_id)`
- FK to `states`
- migration defines cascade delete from state to city

### `Street`

**Kind:** entity  
**Table:** `streets`

Street within a city.

Key fields:

- `id`
- `name`
- `city`
- `addresses`
- `createdAt`
- `updatedAt`

Persistence notes:

- unique constraint on `(name, city_id)`
- FK to `cities`
- migration defines cascade delete from city to street

### `Address`

**Kind:** entity  
**Table:** `address`

Reusable base address record linked to a street. This is intentionally separate from user-specific delivery metadata.

Key fields:

- `id`
- `name`
- `street`
- `createdAt`
- `updatedAt`

Persistence notes:

- FK to `streets`
- delete is restricted at the DB level when downstream relations still reference the row

### Relationship To `AppUserAddress`

`app_user_address` is created by migration `V2__geo_location.sql`, but the Java model for that table lives in `com.bun.platform.appUser.AppUserAddress`.

Boundary:

- `Address` is the reusable location node in the address domain
- `AppUserAddress` adds user-specific delivery metadata such as exact point, building number, apartment, floor, phone, and primary-address semantics

## Services

### `CountryService`

Owns country creation, update, and list retrieval.

Key operations:

- `create(CreateCountryRequest)`
- `update(Long, UpdateCountryDto)`
- `findAllCountries()`

Caching:

- read list cached under `address_cache`
- writes evict the address cache

### `StateService`

Owns state creation, update, and listing by country.

Key operations:

- `create(Long, CreateStateDto)`
- `update(Long, UpdateStateDto)`
- `findStatesByCountry(Long)`

Important rules:

- validates country existence before create
- create delegates geometry acquisition to `StateGeoImportService`
- after import, the created state is reloaded from the repository by `(name, countryId)`
- update may trigger another geo import when name/country changes and `osmQueryEn` is supplied

Implementation note:

- `create(Long countryId, CreateStateDto dto)` receives `countryId` but uses `dto.countryId()` internally as the authoritative value

### `CityService`

Owns city creation, update, and listing by state.

Key operations:

- `create(CreateCityDto)`
- `update(Long, UpdateCityDto)`
- `findCitiesByState(Long)`

Important rules:

- validates state existence before create
- create delegates geometry acquisition to `CityGeoImportService`
- after import, the created city is reloaded from the repository by `(name, stateId)`
- update may trigger another geo import when name/state changes and `osmQueryEn` is supplied

### `StreetService`

Owns street CRUD within a city.

Key operations:

- `create(CreateStreetDto)`
- `update(Long, UpdateStreetDto)`
- `findStreetsByCity(Long)`

Important rules:

- street create/update verifies the target city exists
- list queries return `StreetDto` projections

### `AddressService`

Owns base-address CRUD and the read-model queries used by public and admin APIs.

Key operations:

- `create(CreateAddressDto)`
- `update(Long, UpdateAddressRequest)`
- `deleteById(Long)`
- `findAll()`
- `findAddressHierarchyById(Long)`
- `findAddressById(Long)`
- `findAddressDtoByStreet(Long)`
- `findAddressHirachyDtoByStreet(Long)`
- `findFlatAddressById(Long)`
- `findAllFlatAddresses()`
- `findFlatAddressesByStreetId(Long)`
- `findFlatAddressesByCityId(Long)`
- `findFlatAddressesByStateId(Long)`
- `findFlatAddressesByCountryId(Long)`

Projection styles:

- hierarchical DTO: `GetAddressDto`
- flat DTO: `FlatAddressDto`
- address-by-street DTO: `AddressWithStreetDto`

Operational notes:

- most public reads are cached in `address_cache`
- create/update/delete evict the full address cache
- several older string-based search methods remain but are marked `@Deprecated`

Implementation note:

- `findAddressHirachyDtoByStreet(...)` is spelled with the same typo as the current code

### `StateGeoImportService`

Runs `geo-tools/import_state_polygon.py` through `ProcessBuilder` to import state geometry.

Inputs:

- state name
- country ID
- English OSM query

Exit-code contract:

- `0`: success
- `20`: country not found
- `30`: OSM lookup failed
- `31`: state not found in OSM
- `34`: invalid state geometry

### `CityGeoImportService`

Runs `geo-tools/import_city_polygon.py` through `ProcessBuilder` to import city geometry.

Inputs:

- city name
- state ID
- English OSM query

Exit-code contract:

- `0`: success
- `20`: state not found
- `30`: OSM lookup failed
- `31`: city not found in OSM
- `34`: invalid city geometry

## Repository Surface

### `CountryRepository`

Provides country list projection:

- `findAllCountries()`

### `StateRepository`

Provides:

- `findStatesByCountry(Long)`
- `findStateByCountryAndName(String, Long)`

### `CityRepository`

Provides:

- `findCitiesByState(Long)`
- `findCitiesByStateAndName(String, Long)`

### `StreetRepository`

Provides:

- `findByNameAndCityId(String, Long)`
- `findByCityId(Long)`
- `findByNameContainingIgnoreCase(String)`
- `findAllWithCity()`
- `findStreetsByCity(Long)`

### `AddressRepository`

Provides the richer read model for the domain:

- full-hierarchy fetch joins
- flat projections
- hierarchical projections
- address lookups by street/city/state/country
- primary user address lookup through `AppUserAddress`
- older string-search and aggregation queries

## HTTP Surface

### Public API

Base path: `/api/public/addresses`

Read endpoints:

- `GET /api/public/addresses/{id}`
- `GET /api/public/addresses/street?streetId=...`
- `GET /api/public/addresses/locations/countries`
- `GET /api/public/addresses/locations/states?countryId=...`
- `GET /api/public/addresses/locations/cities?stateId=...`
- `GET /api/public/addresses/locations/streets?cityId=...`
- `GET /api/public/addresses/locations/addresses?streetId=...`

Important implementation note:

- `GET /street?streetId=...` currently calls `findAddressHierarchyById(streetId)` instead of the by-street query, so the method name and behavior are misaligned in the current code

### Admin API

Base path: `/api/admin/address`

Authorization:

- class-level `@PreAuthorize("hasRole('ADMIN')")`

Hierarchy management endpoints:

- `GET /countries`
- `POST /countries`
- `PATCH /countries/{id}`
- `GET /countries/{countryId}/states`
- `POST /states`
- `PATCH /states/{id}`
- `GET /states/{stateId}/cities`
- `POST /cities`
- `PATCH /cities/{id}`
- `GET /cities/{cityId}/streets`
- `POST /streets`
- `PATCH /streets/{id}`
- `GET /addresses`
- `POST /addresses`
- `PATCH /addresses/{id}`
- `DELETE /addresses/{id}`

User-address administration endpoints:

- `GET /users/{userId}/addresses`
- `GET /users/{userId}/addresses/primary`
- `POST /users/{userId}/addresses`
- `DELETE /users/addresses/{userAddressId}`
- `PUT /users/{userId}/addresses/{addressId}/primary`
- `GET /users/{userId}/addresses/{addressId}/exists`
- `GET /users/{userId}/addresses/count`

Security note:

- the admin controller repeatedly resolves the authenticated user from JWT through `UserIdentityService.extractUserIdFromJwt(jwt)`, even where the value is not otherwise used

## Exception Handling

### English

- Address errors should use the bilingual platform envelope and should clearly separate client input problems from geo-import dependency failures.
- `400 Bad Request`: use for malformed address payloads, invalid coordinates, invalid country, state, city, or street relationships, or invalid filter or query input.
- `404 Not Found`: use when the target country, state, city, street, address, or user-address link does not exist.
- `409 Conflict`: use for duplicate hierarchy rows, conflicting hierarchy mutations, or data-constraint violations that prevent the requested change.
- `403 Forbidden`: use when a caller without the required admin authority attempts to mutate geographic data.
- `503 Service Unavailable`: prefer this for `GeoImportException`, external OSM lookup failures, local Python geo-import failures, or temporary GIS dependency outages.
- `500 Internal Server Error`: reserve for unexpected script, geometry, cache, or persistence failures that are not safely classifiable as dependency errors.
- Current implementation note: `GeoImportException` exists in the codebase, but the global handler does not yet map it explicitly, so documenting the intended contract here exposes the normalization gap.

### العربية

- يجب أن تستخدم أخطاء نطاق العناوين غلاف الأخطاء ثنائي اللغة، مع فصل واضح بين مشاكل إدخال العميل وبين أعطال تبعيات الاستيراد الجغرافي.
- `400 طلب غير صحيح`: يستخدم عند وجود حمولة عنوان مشوهة، أو إحداثيات غير صالحة، أو علاقة غير صحيحة بين الدولة والولاية والمدينة والشارع، أو مدخلات استعلام أو ترشيح غير صحيحة.
- `404 غير موجود`: يستخدم عندما لا تكون الدولة أو الولاية أو المدينة أو الشارع أو العنوان أو علاقة عنوان المستخدم موجودة.
- `409 تعارض`: يستخدم عند وجود صفوف مكررة في التسلسل الجغرافي، أو تعديلات متعارضة على الهيكل الهرمي، أو قيود بيانات تمنع تنفيذ التغيير المطلوب.
- `403 ممنوع`: يستخدم عندما يحاول مستدعٍ لا يملك صلاحية المدير المطلوبة تعديل البيانات الجغرافية.
- `503 الخدمة غير متاحة`: يفضل استخدامه مع `GeoImportException`، أو عند فشل البحث الخارجي في OSM، أو فشل سكربتات الاستيراد المحلية، أو تعطل تبعيات GIS بشكل مؤقت.
- `500 خطأ داخلي في الخادم`: يحجز لأعطال السكربتات أو الهندسة المكانية أو الكاش أو التخزين عندما لا يمكن تصنيفها بأمان كأخطاء تبعية خارجية.
- ملاحظة تنفيذية حالية: الاستثناء `GeoImportException` موجود في الكود، لكن المعالج العام لا يربطه صراحة حتى الآن، ولذلك يوضح هذا التوثيق الفجوة الحالية في توحيد الاستجابات.

## Persistence Summary

Migration `V2__geo_location.sql` defines the address schema.

Primary tables:

- `countries`
- `states`
- `cities`
- `streets`
- `address`
- `app_user_address`

Key relationships:

- one `Country` to many `State`
- one `State` to many `City`
- one `City` to many `Street`
- one `Street` to many `Address`
- one `Address` to many `AppUserAddress`

Geometry support:

- `states.geom`: polygon
- `states.centroid`: point
- `cities.geom`: polygon
- `cities.centroid`: point
- `app_user_address.location`: point

Indexes of note:

- `idx_state_geom`
- `idx_state_centroid`
- `idx_city_geom`
- `idx_city_centroid`
- `idx_user_address_location`

## End-to-End Flows

### Public Hierarchy Browsing

1. Client requests countries
2. Client requests states by country
3. Client requests cities by state
4. Client requests streets by city
5. Client requests addresses for the selected street

This flow is projection-oriented and mostly served from cache after first read.

### Admin State Creation With Geo Import

1. Admin posts `CreateStateDto`
2. `StateService` verifies the country exists
3. `StateGeoImportService` runs the Python import script
4. Script writes state row and geometry data into the database
5. Service reloads the created state by `(stateName, countryId)`
6. Cache entries are evicted

### Admin City Creation With Geo Import

1. Admin posts `CreateCityDto`
2. `CityService` verifies the state exists
3. `CityGeoImportService` runs the Python import script
4. Script writes city row and geometry data into the database
5. Service reloads the created city by `(cityName, stateId)`
6. Cache entries are evicted

### User Address Assignment

1. Admin or user-facing app-user services choose a reusable `Address`
2. `AppUserAddressService` creates or updates the `app_user_address` row
3. Exact delivery point and user-specific metadata are stored on the junction
4. Seller, order, and shipment flows can reference the resulting address records

## Design Constraints And Observations

- The domain deliberately separates reusable geographic addresses from user-specific delivery details
- State and city creation depend on external Python geo-import scripts rather than pure JPA writes
- Public APIs expose DTO projections instead of entire entity graphs for most lookup flows
- Caching is broad and simple: writes usually evict all address cache entries
- The schema is GIS-aware, but the Java services only expose a small subset of geometric behavior directly
- Some legacy search methods remain in `AddressService`, but they are marked deprecated and are not the primary API surface

## Improvement Areas

- Fix the public `/street` lookup path so it actually uses the by-street query instead of calling the by-id lookup with `streetId`.
- Remove or fully retire deprecated string-based search methods once the projection-based API is the only supported path.
- Reduce cache invalidation blast radius. Current write paths often evict the full `address_cache`.
- Make geo-import dependencies explicit in runtime docs and health checks because state/city creation depends on local Python scripts and external geo lookups.
- Tighten service signatures such as `StateService.create(...)` so the passed method parameters and DTO authority are not ambiguous.
