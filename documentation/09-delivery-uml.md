# Delivery UML

## Class Diagram

```mermaid
classDiagram
    class AppUser {
        <<external identity domain>>
        +Long id
        +String username
        +String name
        +String phone
        +Set~Role~ roles
    }

    class Seller {
        <<external seller domain>>
        +Long id
        +Long appUserAddressId
    }

    class DeliveryCompany {
        +Long id
        +boolean active
        +Instant createdAt
        +Instant updatedAt
    }

    class Driver {
        +Long id
        +boolean active
        +DriverOperationalStatus operationalStatus
        +String phone
        +String notes
        +DriverTrackingSnapshot tracking
        +Long version
        +getOwnerType()
        +deactivate(now)
        +reactivate(now)
    }

    class DriverTrackingSnapshot {
        +String locationDescription
        +String mapUrl
        +Point position
        +Double latitude
        +Double longitude
        +Instant updatedAt
    }

    class Shipment {
        +Long id
        +Long orderId
        +Long sellerId
        +Long customerId
        +Long deliveryCompanyId
        +Long assignedDriverId
        +DeliveryOwnershipType deliveryOwnershipType
        +ShipmentStatus status
        +ShipmentAddressSnapshot pickup
        +ShipmentAddressSnapshot delivery
        +ShipmentCustomerContact customerContact
        +BigDecimal deliveryFee
        +BigDecimal itemsTotal
        +BigDecimal totalAmount
        +Instant readyAt
        +Instant assignedAt
        +Instant outForDeliveryAt
        +Instant deliveredAt
        +Instant failedAt
        +Instant canceledAt
        +Long version
        +replaceItems(items)
        +recomputeTotals()
    }

    class ShipmentAddressSnapshot {
        +Long addressId
        +String addressText
        +String mapUrl
        +Point location
        +Double latitude
        +Double longitude
    }

    class ShipmentCustomerContact {
        +String name
        +String phone
    }

    class ShipmentItem {
        +Long id
        +Long orderItemId
        +String productName
        +Integer qty
        +BigDecimal unitPriceSnapshot
        +BigDecimal lineAmount
        +safeLineAmount()
    }

    class Address {
        <<external address domain>>
        +Long id
        +String name
    }

    class FlatAddressDto {
        <<address read model>>
        +Long addressId
        +String addressName
        +Long streetId
        +String streetName
        +Long cityId
        +String cityName
        +Long stateId
        +String stateName
        +Long countryId
        +String countryName
    }

    class DeliveryCompanyService {
        +createDeliveryCompany(appUserId, deviceId)
        +getOwnCompany(companyId)
        +listActiveCompanies()
    }

    class DriverService {
        +createSellerDriver(sellerId, request)
        +createDeliveryCompanyDriver(companyId, request)
        +createFreelancerDriver(request)
        +listSellerDrivers(sellerId, active, status)
        +listDeliveryCompanyDrivers(companyId, active, status)
        +listFreelancerDrivers(active, status)
        +refreshWorkloadStatus(driverId)
    }

    class ShipmentService {
        +createShipment(sellerId, request)
        +markReady(sellerId, shipmentId)
        +assignSellerDriver(sellerId, shipmentId, request)
        +assignDeliveryCompanyDriver(companyId, shipmentId, request)
        +getOwnedShipment(sellerId, shipmentId)
        +getDeliveryCompanyManagedShipment(companyId, shipmentId)
    }

    class ShipmentFeeCalculator {
        +resolveForCreate(shipment, requestedFee, fallbackFee)
        +resolveForUpdate(shipment, requestedFee, locationChanged)
        +calculate(shipment)
    }

    AppUser "1" --> "0..1" Seller : seller account
    AppUser "1" --> "0..1" DeliveryCompany : delivery company account
    AppUser "1" --> "0..1" Driver : driver account

    Seller "1" --> "0..*" Driver : seller-managed drivers
    DeliveryCompany "1" --> "0..*" Driver : outsourced drivers
    Driver *-- DriverTrackingSnapshot

    Shipment "1" --> "0..*" ShipmentItem : contains
    Shipment *-- ShipmentAddressSnapshot
    Shipment *-- ShipmentCustomerContact
    Shipment ..> Seller : sellerId
    Shipment ..> DeliveryCompany : deliveryCompanyId
    Shipment ..> Driver : assignedDriverId
    Shipment ..> Address : pickupAddressId
    Shipment ..> Address : deliveryAddressId
    Shipment ..> FlatAddressDto : detail response enrichment

    DeliveryCompanyService --> DeliveryCompany
    DeliveryCompanyService --> FlatAddressDto : primaryAddress
    DriverService --> Driver
    ShipmentService --> Shipment
    ShipmentService --> ShipmentFeeCalculator
    ShipmentService --> FlatAddressDto : pickup and delivery read models
```

## Ownership View

```mermaid
flowchart LR
    Seller["Seller"] -->|"owns shipment record"| Shipment["Shipment"]
    Seller -->|"may manage delivery directly"| SellerDriver["Seller Driver"]
    Seller -->|"may assign platform freelancer"| FreelancerDriver["Freelancer Driver"]

    Shipment -->|"DELIVERY_OWNERSHIP_TYPE = MERCHANT"| SellerOps["Seller-operated flow"]
    Shipment -->|"DELIVERY_OWNERSHIP_TYPE = DELIVERY_COMPANY"| CompanyOps["Delivery-company flow"]
    Shipment -->|"DELIVERY_OWNERSHIP_TYPE = FREE_LANCER"| FreelancerOps["Seller + freelancer flow"]
    Shipment -->|"DELIVERY_OWNERSHIP_TYPE = EXTERNAL_MANUAL"| ManualOps["Manual / external flow"]

    DeliveryCompany["DeliveryCompany"] -->|"manages"| CompanyDriver["Delivery Company Driver"]
    CompanyOps --> CompanyDriver
    SellerOps --> SellerDriver
    FreelancerOps --> FreelancerDriver
    ManualOps --> Notes["Notes, phone, map URL, geo point, manual follow-up"]
```

## Seller Shipment Creation Sequence

```mermaid
sequenceDiagram
    participant Seller
    participant ShipmentController
    participant ShipmentService
    participant SellerRepository
    participant OrderRepository
    participant AddressRepository
    participant AppUserAddressRepository
    participant ShipmentRepository

    Seller->>ShipmentController: POST /api/seller/delivery/shipments
    ShipmentController->>ShipmentService: createShipment(sellerId, request)
    ShipmentService->>SellerRepository: findById(sellerId)
    SellerRepository-->>ShipmentService: Seller
    ShipmentService->>OrderRepository: findOrderDetailsByIdAndSellerId(orderId, sellerId)
    OrderRepository-->>ShipmentService: Order or empty
    ShipmentService->>AddressRepository: findFlatAddressById(pickupAddressId)
    AddressRepository-->>ShipmentService: FlatAddressDto
    ShipmentService->>AddressRepository: findFlatAddressById(deliveryAddressId)
    AddressRepository-->>ShipmentService: FlatAddressDto
    ShipmentService->>AppUserAddressRepository: resolve pickup/delivery point when available
    AppUserAddressRepository-->>ShipmentService: AppUserAddress or empty
    ShipmentService->>ShipmentRepository: save(shipment)
    ShipmentRepository-->>ShipmentService: Shipment
    ShipmentService-->>ShipmentController: ShipmentResponse
    ShipmentController-->>Seller: 201 Created
```

## Delivery Company Assignment Sequence

```mermaid
sequenceDiagram
    participant Company as DeliveryCompany
    participant DeliveryCompanyShipmentController
    participant ShipmentService
    participant ShipmentRepository
    participant DriverRepository
    participant DriverService

    Company->>DeliveryCompanyShipmentController: POST /api/delivery-company/delivery/shipments/{id}/assign-driver
    DeliveryCompanyShipmentController->>ShipmentService: assignDeliveryCompanyDriver(companyId, shipmentId, request)
    ShipmentService->>ShipmentRepository: findDetailsByIdAndDeliveryCompanyId(shipmentId, companyId)
    ShipmentRepository-->>ShipmentService: Shipment
    ShipmentService->>DriverRepository: findByIdAndDeliveryCompanyId(driverId, companyId)
    DriverRepository-->>ShipmentService: Driver
    ShipmentService->>ShipmentRepository: save(shipment with ASSIGNED)
    ShipmentService->>DriverRepository: save(driver with BUSY if needed)
    ShipmentService->>DriverService: refreshWorkloadStatus(previousDriverId) if reassigned
    ShipmentService-->>DeliveryCompanyShipmentController: ShipmentResponse
    DeliveryCompanyShipmentController-->>Company: 200 OK
```

## Seller Freelancer Assignment Sequence

```mermaid
sequenceDiagram
    participant Seller
    participant ShipmentController
    participant ShipmentService
    participant ShipmentRepository
    participant DriverRepository
    participant DriverService

    Seller->>ShipmentController: POST /api/seller/delivery/managed-shipments/{id}/assign-driver
    ShipmentController->>ShipmentService: assignSellerDriver(sellerId, shipmentId, request)
    ShipmentService->>ShipmentRepository: findDetailsByIdAndSellerId(shipmentId, sellerId)
    ShipmentRepository-->>ShipmentService: Shipment with FREE_LANCER ownership
    ShipmentService->>DriverRepository: findFreelancerById(driverId)
    DriverRepository-->>ShipmentService: Freelancer Driver
    ShipmentService->>ShipmentRepository: save(shipment with ASSIGNED)
    ShipmentService->>DriverRepository: save(driver with BUSY if needed)
    ShipmentService->>DriverService: refreshWorkloadStatus(previousDriverId) if reassigned
    ShipmentService-->>ShipmentController: ShipmentResponse
    ShipmentController-->>Seller: 200 OK
```

## Shipment Detail Read With Address Enrichment

```mermaid
sequenceDiagram
    actor User
    participant Ctrl as AnyDeliveryController
    participant Service as ShipmentService
    participant ShipRepo as ShipmentRepository
    participant AddrRepo as AddressRepository

    User->>Ctrl: GET shipment details
    Ctrl->>Service: getShipmentDetails
    Service->>ShipRepo: findShipmentDetails
    ShipRepo-->>Service: Shipment with items
    Service->>AddrRepo: findFlatAddressById pickupAddressId
    AddrRepo-->>Service: FlatAddressDto or null
    Service->>AddrRepo: findFlatAddressById deliveryAddressId
    AddrRepo-->>Service: FlatAddressDto or null
    Service-->>Ctrl: ShipmentResponse with enriched addresses
    Ctrl-->>User: 200 OK
```

## Shipment Lifecycle

```mermaid
stateDiagram-v2
    [*] --> DRAFT
    DRAFT --> READY : complete minimum delivery data
    FAILED --> READY : retry

    READY --> ASSIGNED : assign driver
    ASSIGNED --> ASSIGNED : reassign driver

    READY --> OUT_FOR_DELIVERY : manager starts manual flow
    ASSIGNED --> OUT_FOR_DELIVERY : manager or driver starts run

    READY --> DELIVERED : manager closes manual delivery
    ASSIGNED --> DELIVERED : manager or driver completes
    OUT_FOR_DELIVERY --> DELIVERED : manager or driver completes

    READY --> FAILED : manager marks failed
    ASSIGNED --> FAILED : manager or driver marks failed
    OUT_FOR_DELIVERY --> FAILED : manager or driver marks failed

    DRAFT --> CANCELED : manager cancels
    READY --> CANCELED : manager cancels
    ASSIGNED --> CANCELED : manager cancels
    FAILED --> CANCELED : manager cancels
```

## Address-Domain Integration View

```mermaid
flowchart TD
    A["Shipment stores pickupAddressId + deliveryAddressId + PostGIS points"] --> B["ShipmentService.resolveAddressText(...)"]
    A --> C["ShipmentService.findFlatAddress(...)"]
    A --> J["Pickup / delivery point supports ST_DWithin and distance calculations"]
    D["DeliveryCompany account"] --> E["AddressRepository.findPrimaryAddress(appUserId)"]
    K["ShipmentService"] --> L["AppUserAddressRepository resolves seller/customer point when available"]
    E --> F["AddressRepository.findFlatAddressById(addressId)"]
    C --> G["ShipmentResponse.pickupAddress / deliveryAddress"]
    F --> H["DeliveryCompanyResponse.primaryAddress"]
    B --> I["Gaza-friendly fallback text snapshot"]
    L --> A
```
