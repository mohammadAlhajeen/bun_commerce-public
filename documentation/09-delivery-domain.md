# Delivery Domain MVP

## Goal

This module provides a practical delivery subsystem for Gaza-focused marketplace operations.

It is intentionally:

- simple
- operational
- tolerant of partial data
- loosely coupled from order, payment, and inventory internals

Shipment is treated as a provisional operational record, not as the center of logistics complexity.

Related diagrams: `documentation/09-delivery-uml.md`

## Domain Design

### 1. Driver

`Driver` is the operational delivery actor managed by a seller, a delivery company, or kept ownerless as a freelancer.

Core fields:

- `id`
- `appUser`
- `seller`
- `deliveryCompany`
- `ownerType`
- `phone`
- `tracking`
- `active`
- `operationalStatus`
- `notes`
- `createdAt`
- `updatedAt`
- `version`

Design note:
`active` is administrative eligibility. `operationalStatus` is day-to-day state.
`tracking` is a small value object so operational updates stay grouped. It now stores:

- human-readable location text
- optional legacy map URL
- PostGIS `Point` for dispatch/radius calculations

Driver phone remains a direct scalar because the MVP only needs one essential contact field.

### 2. Shipment

`Shipment` is a lightweight operational delivery record.

Core fields:

- `id`
- `orderId`
- `sellerId`
- `customerId`
- `deliveryCompanyId`
- `deliveryOwnershipType`
- `assignedDriverId`
- `status`
- `trackingNumber`
- `pickup`
- `delivery`
- `deliveryNotes`
- `failureReason`
- `customerContact`
- `deliveryFee`
- `itemsTotal`
- `totalAmount`
- `readyAt`
- `assignedAt`
- `outForDeliveryAt`
- `deliveredAt`
- `failedAt`
- `canceledAt`
- `createdAt`
- `updatedAt`
- `version`

Design note:
Shipment only keeps scalar references plus snapshots. It does not own order lifecycle, payment capture, or inventory allocation.
`pickup`, `delivery`, and `customerContact` are value objects to keep the entity readable while preserving a lightweight shipment schema.
Each shipment address snapshot now keeps:

- normalized address reference when available
- display text snapshot
- optional legacy map URL for manual operations
- PostGIS `Point` for routing, delivery-fee, and geo queries

### 3. Shipment Item

`ShipmentItem` is supportive snapshot data only.

Core fields:

- `id`
- `shipment`
- `orderItemId`
- `productName`
- `qty`
- `unitPriceSnapshot`
- `lineAmount`

Design note:
`orderItemId` is optional. This allows manual delivery requests that are not tightly coupled to order internals.

### 4. Delivery Ownership

This separates merchant ownership from delivery execution.

- `sellerId`: merchant that owns the order / shipment record
- `deliveryCompanyId`: nullable outsourced delivery company currently responsible for delivery operations
- `deliveryOwnershipType`: how delivery is being handled

This keeps the model usable for:

- merchant-managed delivery
- freelancer delivery
- platform delivery companies
- external/manual delivery visibility

## Aggregate Boundaries

### Driver aggregate

Owns:

- activation / deactivation
- operational status
- last known operational info and position

Does not own:

- shipment workflow
- pricing
- payroll

### Shipment aggregate

Owns:

- operational shipment state
- delivery company reference
- driver assignment reference
- address references plus geo-capable snapshots
- operational timestamps

Does not own:

- order fulfillment rules
- payment settlement
- inventory movement
- routing

## Spatial Model

The delivery module now supports native PostGIS points in the operational aggregates.

### Shipment pickup / delivery

`ShipmentAddressSnapshot` stores a `Point` in addition to the legacy locator text and URL.

Resolution order inside `ShipmentService`:

1. explicit request latitude / longitude
2. parseable legacy coordinate string or map URL
3. `AppUserAddress.location` for the seller pickup or customer delivery address

This keeps the API tolerant of older clients while making the persisted shipment usable for:

- shipping-fee calculation
- route estimation
- nearest-driver selection
- zone checks with `ST_DWithin`

### Driver tracking

`DriverTrackingSnapshot` stores `last_known_position` as a PostGIS `Point`.

Operational updates can still include:

- a human-readable location description
- a legacy map URL

But dispatch logic can now query on actual coordinates rather than string payloads.

## Shipment Fee Calculation

Shipment fees are now resolved through `ShipmentFeeCalculator`, which wraps the existing
distance-based `ShippingCalculator`.

Resolution order:

1. explicit `deliveryFee` from the request
2. calculated fee when both pickup and delivery points are present
3. fallback fee from the source order on shipment creation
4. existing shipment fee on shipment update when recalculation is not possible

The default pricing policy is configuration-based:

- `shipment.pricing.price-per-unit`
- `shipment.pricing.shipping-unit-km`

This keeps the current implementation production-usable without introducing a premature
per-company tariff model.

## Enums

### DriverOperationalStatus

- `AVAILABLE`
- `BUSY`
- `OFFLINE`

### DeliveryOwnershipType

- `MERCHANT`
- `DELIVERY_COMPANY`
- `FREE_LANCER`
- `EXTERNAL_MANUAL`

### ShipmentStatus

- `DRAFT`
- `READY`
- `ASSIGNED`
- `OUT_FOR_DELIVERY`
- `DELIVERED`
- `FAILED`
- `CANCELED`

## Main Use Cases

### Driver management

- create driver for a seller
- create driver for a delivery company
- create freelancer driver
- activate driver
- deactivate driver
- update operational status
- list seller drivers
- list delivery company drivers
- list freelancer drivers
- get single driver details

### Shipment management

- create shipment from order snapshot or manual request
- update shipment operational fields
- mark shipment ready
- assign driver
- unassign driver
- move shipment to out for delivery
- mark delivered
- mark failed
- cancel shipment

### Visibility

- list seller-owned shipments
- list seller-operated shipments
- list delivery-company-managed shipments
- list driver-assigned shipments
- admin inspection across all shipments
- show driver workload count

## Service Responsibilities

### `DriverService`

- create driver accounts
- keep driver ownership boundaries intact
- manage activation and operational status
- normalize driver tracking coordinates from explicit lat/lng or parseable legacy URLs
- expose driver views for seller, delivery company, freelancer driver, and admin
- refresh workload-based status after shipment changes

### `ShipmentService`

- create shipment snapshots from seller input and optional order data
- normalize pickup and delivery points from request data, legacy coordinate strings, or user addresses
- delegate delivery-fee resolution to `ShipmentFeeCalculator`
- keep shipment validation explicit and local
- enforce simple lifecycle guards
- validate assignment rules
- expose seller-owned, seller-operated, delivery-company-operated, driver, and admin views
- map shipment data into operational DTOs

## Repository Design

### `DriverRepository`

- find driver by seller
- find driver by delivery company
- find freelancer driver
- search drivers by seller / delivery company / active / status

### `ShipmentRepository`

- search shipments by seller / delivery company / driver / status
- load shipment details with items
- count active assigned shipments per driver

### Supporting repositories

- `SellerRepository`
- `DeliveryCompanyRepository`
- `OrderRepository`
- `AddressRepository`
- `AppUserAddressRepository`
- `AppUserRepository`

## Validation Rules

### Driver

- username must be unique
- inactive drivers cannot become available/busy until reactivated
- assignment rejects inactive drivers
- assignment rejects offline drivers

### Shipment creation

- seller must exist
- if `orderId` is provided, it must belong to the seller
- `DELIVERY_COMPANY` requires a valid internal company id
- `MERCHANT`, `FREE_LANCER`, and `EXTERNAL_MANUAL` normalize `deliveryCompanyId` to `null`
- item quantities must be at least 1

### Shipment readiness

- customer phone required
- at least one delivery locator required
  - address id, snapshot text, map URL, or geo point
- at least one pickup locator required
  - address id, snapshot text, map URL, or geo point

### Assignment

- shipment must be `READY`, `ASSIGNED`, or `FAILED`
- `EXTERNAL_MANUAL` shipments cannot be assigned to platform drivers
- seller drivers must belong to the seller
- freelancer drivers must not belong to a seller or delivery company
- delivery-company drivers must belong to the delivery company

### Status transitions

- `DRAFT` or `FAILED` -> `READY`
- `READY` / `ASSIGNED` / `FAILED` -> driver assignment
- `ASSIGNED` / `READY` -> `OUT_FOR_DELIVERY` for manager, with driver requirement except external manual
- `ASSIGNED` -> `OUT_FOR_DELIVERY` for driver
- `READY` / `ASSIGNED` / `OUT_FOR_DELIVERY` -> `DELIVERED` or `FAILED` for manager
- `ASSIGNED` / `OUT_FOR_DELIVERY` -> `DELIVERED` or `FAILED` for driver
- any non-delivered, non-canceled shipment -> `CANCELED` for the active manager

## REST API

### Seller driver endpoints

- `POST /api/seller/delivery/drivers`
- `GET /api/seller/delivery/drivers`
- `GET /api/seller/delivery/drivers/{driverId}`
- `PATCH /api/seller/delivery/drivers/{driverId}/active`
- `PATCH /api/seller/delivery/drivers/{driverId}/status`

### Freelancer driver endpoints

- `GET /api/seller/delivery/freelancer-drivers`
- `GET /api/seller/delivery/freelancer-drivers/{driverId}`
- `POST /api/admin/delivery/freelancer-drivers`
- `GET /api/admin/delivery/freelancer-drivers`
- `GET /api/admin/delivery/freelancer-drivers/{driverId}`
- `PATCH /api/admin/delivery/freelancer-drivers/{driverId}/active`
- `PATCH /api/admin/delivery/freelancer-drivers/{driverId}/status`

### Driver self endpoints

- `GET /api/driver/delivery/me`
- `PATCH /api/driver/delivery/me/status`

### Delivery company endpoints

- `POST /api/delivery-company/register`
- `GET /api/delivery-company/me`
- `GET /api/seller/delivery/companies`
- `GET /api/admin/delivery/companies`

### Delivery company driver endpoints

- `POST /api/delivery-company/drivers`
- `GET /api/delivery-company/drivers`
- `GET /api/delivery-company/drivers/{driverId}`
- `PATCH /api/delivery-company/drivers/{driverId}/active`
- `PATCH /api/delivery-company/drivers/{driverId}/status`

### Seller shipment endpoints

- `POST /api/seller/delivery/shipments`
- `PATCH /api/seller/delivery/shipments/{shipmentId}`
- `POST /api/seller/delivery/shipments/{shipmentId}/ready`
- `GET /api/seller/delivery/shipments`
- `GET /api/seller/delivery/shipments/{shipmentId}`

### Seller-operated shipment endpoints

- `GET /api/seller/delivery/managed-shipments`
- `GET /api/seller/delivery/managed-shipments/{shipmentId}`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/assign-driver`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/unassign-driver`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/out-for-delivery`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/deliver`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/fail`
- `POST /api/seller/delivery/managed-shipments/{shipmentId}/cancel`

### Delivery company shipment endpoints

- `GET /api/delivery-company/delivery/shipments`
- `GET /api/delivery-company/delivery/shipments/{shipmentId}`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/assign-driver`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/unassign-driver`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/out-for-delivery`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/deliver`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/fail`
- `POST /api/delivery-company/delivery/shipments/{shipmentId}/cancel`

### Driver shipment endpoints

- `GET /api/driver/delivery/shipments`
- `GET /api/driver/delivery/shipments/{shipmentId}`
- `POST /api/driver/delivery/shipments/{shipmentId}/out-for-delivery`
- `POST /api/driver/delivery/shipments/{shipmentId}/deliver`
- `POST /api/driver/delivery/shipments/{shipmentId}/fail`

### Admin inspection endpoints

- `GET /api/admin/delivery/drivers`
- `GET /api/admin/delivery/drivers/{driverId}`
- `GET /api/admin/delivery/shipments`
- `GET /api/admin/delivery/shipments/{shipmentId}`

## DTOs

### Driver

- `CreateDriverRequest`
- `SetDriverActiveRequest`
- `UpdateDriverStatusRequest`
- `DriverResponse`
- `DriverSummaryResponse`

Driver status DTOs now accept and return:

- `lastKnownLatitude`
- `lastKnownLongitude`
- `lastKnownMapUrl` as a backward-compatible field for legacy clients

### Shipment

- `CreateShipmentRequest`
- `UpdateShipmentRequest`
- `AssignShipmentRequest`
- `FailShipmentRequest`
- `ShipmentItemRequest`
- `ShipmentItemResponse`
- `ShipmentSummaryResponse`
- `ShipmentResponse`

Shipment DTOs now accept and return:

- `pickupLatitude`
- `pickupLongitude`
- `deliveryLatitude`
- `deliveryLongitude`
- legacy `pickupMapUrl` / `deliveryMapUrl` alongside the new coordinates

## Roadmap

### Phase 1: Minimal driver + shipment management

- driver creation and activation
- freelancer driver creation and seller assignment
- seller-owned and seller-operated shipment views
- delivery-company registration and outsourced shipment operations
- basic assignment
- basic status lifecycle
- address-domain lookup plus Gaza-friendly snapshots and notes

### Phase 2: Better assignment and operational tracking

- reassignment reasons
- driver workload dashboard
- richer operational notes
- shipment event timeline
- spatial driver updates and geo-indexed dispatch queries

### Phase 3: Future extensibility

- replaceable shipment workflow module
- pricing strategy abstraction
- external courier adapters
- route batches / delivery runs
- audit/event stream for logistics-grade observability
