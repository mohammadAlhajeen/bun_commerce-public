# Checkout UML And Flow Diagrams

## Context And Boundaries

```mermaid
flowchart LR
    Cart["Cart domain\nmutable shopping intent"] -->|validateCartForReconcile| Preview["Checkout preview"]
    Preview -->|stateless pricing| Pricing["CheckoutPricingService"]
    Preview -->|no persistence| UI["Frontend"]

    UI -->|confirm| Confirm["CheckoutApplicationService.confirmCheckout"]
    Confirm -->|reconcile again| Cart
    Confirm -->|re-price again| Pricing
    Confirm -->|reserve/commit| Inventory["Inventory domain"]
    Confirm -->|persist snapshot| Checkout["Checkout aggregate"]
    Confirm -->|create committed transaction| Order["Order domain"]
```

## Class Diagram

```mermaid
classDiagram
    class Cart {
        <<external cart aggregate>>
        +id
        +customerId
        +sellerId
        +items
        +closed
    }

    class Checkout {
        +id
        +checkoutNumber
        +sourceCartId
        +customerId
        +sellerId
        +status
        +shippingAddress
        +contact
        +couponCode
        +couponApplied
        +couponDescription
        +couponDiscountTotal
        +shippingMethodCode
        +shippingMethodLabel
        +subtotalAmount
        +itemDiscountTotal
        +shippingTotal
        +grandTotal
        +orderId
        +orderNumber
        +inventoryReservedAt
        +inventoryReservationExpiresAt
        +expiresAt
        +attachOrder(orderId, orderNumber)
        +markInventoryReserved(reservedAt, expiresAt)
    }

    class CheckoutItem {
        +id
        +cartItemId
        +variantId
        +productId
        +productName
        +variantName
        +inventoryPolicy
        +variantPurchaseVersion
        +quantity
        +unitBasePrice
        +unitDiscount
        +unitFinalPrice
        +lineSubtotal
        +lineDiscount
        +lineTotal
    }

    class CheckoutItemSelection {
        +id
        +attributeId
        +attributeName
        +valueId
        +valueText
    }

    class CheckoutAddressSnapshot {
        +userAddressId
        +addressId
        +addressName
        +street
        +city
        +state
        +country
        +buildingNumber
        +apartmentNumber
        +floor
        +additionalInfo
        +addressPhone
        +latitude
        +longitude
    }

    class CheckoutContactSnapshot {
        +name
        +phone
    }

    class CheckoutPricingService {
        <<stateless>>
        +calculate(request)
    }

    class CheckoutShippingService {
        <<stateless>>
        +quote(request)
    }

    class CheckoutCouponService {
        <<stateless>>
        +applyCoupon(request)
    }

    class InventoryReservationService {
        <<integration service>>
        +reserve(lines)
        +commit(lines)
        +release(lines)
    }

    class CheckoutApplicationService {
        +prepareCheckoutPreview(customerId, request)
        +confirmCheckout(customerId, request)
        +getCheckoutSummary(customerId, checkoutId)
    }

    class CheckoutOrderFactory {
        +buildCheckout(prepared, variants, reservedAt, expiresAt)
        +buildOrder(checkout, prepared)
    }

    class Order {
        <<external order aggregate>>
        +id
        +orderNumber
        +status
        +paymentStatus
    }

    Cart ..> CheckoutApplicationService
    CheckoutApplicationService --> CheckoutPricingService
    CheckoutApplicationService --> InventoryReservationService
    CheckoutApplicationService --> CheckoutOrderFactory
    CheckoutOrderFactory --> Checkout
    CheckoutOrderFactory --> Order
    Checkout "1" *-- "1..*" CheckoutItem
    CheckoutItem "1" *-- "0..*" CheckoutItemSelection
    Checkout *-- CheckoutAddressSnapshot
    Checkout *-- CheckoutContactSnapshot
    Checkout ..> Cart : sourceCartId only
    Checkout ..> Order : orderId / orderNumber only
    CheckoutPricingService --> CheckoutShippingService
    CheckoutPricingService --> CheckoutCouponService
```

## Preview Sequence

```mermaid
sequenceDiagram
    participant Customer
    participant CheckoutController
    participant CheckoutApplicationService
    participant CartRepository
    participant CartValidationService
    participant CheckoutInputResolver
    participant CheckoutPricingService

    Customer->>CheckoutController: POST /api/checkouts/preview
    CheckoutController->>CheckoutApplicationService: prepareCheckoutPreview(customerId, request)
    CheckoutApplicationService->>CartRepository: findWithItemsByIdAndCustomerIdForUpdate(cartId, customerId)
    CartRepository-->>CheckoutApplicationService: Cart
    CheckoutApplicationService->>CartValidationService: validateCartForReconcile(cartId)
    CartValidationService-->>CheckoutApplicationService: CartView
    CheckoutApplicationService->>CheckoutInputResolver: resolve(customerId, addressId, recipient, phone, notes)
    CheckoutInputResolver-->>CheckoutApplicationService: ResolvedCheckoutInput
    CheckoutApplicationService->>CheckoutPricingService: calculate(pricingRequest)
    CheckoutPricingService-->>CheckoutApplicationService: CheckoutPricingResult
    CheckoutApplicationService-->>CheckoutController: CheckoutPreviewResponse
    CheckoutController-->>Customer: 200 OK
```

## Confirm Sequence

```mermaid
sequenceDiagram
    participant Customer
    participant CheckoutController
    participant CheckoutApplicationService
    participant CartValidationService
    participant CheckoutPricingService
    participant InventoryReservationService
    participant CheckoutRepository
    participant OrderRepository

    Customer->>CheckoutController: POST /api/checkouts/confirm
    CheckoutController->>CheckoutApplicationService: confirmCheckout(customerId, request)
    rect rgb(240, 248, 255)
        Note over CheckoutApplicationService,OrderRepository: single database transaction
        CheckoutApplicationService->>CartValidationService: validateCartForReconcile(cartId)
        CartValidationService-->>CheckoutApplicationService: CartView
        CheckoutApplicationService->>CheckoutPricingService: calculate(pricingRequest)
        CheckoutPricingService-->>CheckoutApplicationService: CheckoutPricingResult
        CheckoutApplicationService->>InventoryReservationService: reserve(reservationLines)
        InventoryReservationService-->>CheckoutApplicationService: reserved
        CheckoutApplicationService->>CheckoutRepository: save(checkout snapshot)
        CheckoutRepository-->>CheckoutApplicationService: Checkout
        CheckoutApplicationService->>OrderRepository: save(order)
        OrderRepository-->>CheckoutApplicationService: Order
        CheckoutApplicationService->>CheckoutRepository: save(checkout with order linkage)
        CheckoutApplicationService->>InventoryReservationService: commit(reservationLines)
    end
    CheckoutApplicationService-->>CheckoutController: CheckoutConfirmationResponse
    CheckoutController-->>Customer: 200 OK
```

## Transaction Boundary View

```mermaid
flowchart TD
    A["Lock cart"] --> B["Reconcile cart again"]
    B --> C["Resolve snapshot inputs"]
    C --> D["Recalculate pricing again"]
    D --> E{"confirmable?"}
    E -- "No" --> X["throw and rollback"]
    E -- "Yes" --> F["Reserve tracked inventory"]
    F --> G["Persist Checkout snapshot"]
    G --> H["Create Order"]
    H --> I["Link Checkout to Order"]
    I --> J["Commit reserved inventory"]
    J --> K["Close cart"]
    K --> L["commit transaction"]
```

## Lifecycle State Diagram

```mermaid
stateDiagram-v2
    [*] --> ORDER_CREATED : current direct confirm flow

    ORDER_CREATED --> CANCELLED : future cancellation path
    ORDER_CREATED --> EXPIRED : future expiry policy if checkout remains open

    [*] --> PENDING_PAYMENT : future payment-aware flow
    PENDING_PAYMENT --> ORDER_CREATED : payment success
    PENDING_PAYMENT --> EXPIRED : TTL elapsed
    PENDING_PAYMENT --> CANCELLED : user/system cancellation
```

## Reservation And Failure Model

```mermaid
flowchart LR
    A["Reserve tracked inventory"] --> B{"later step fails?"}
    B -- "Yes" --> C["transaction rollback"]
    C --> D["reservation disappears with rollback"]
    B -- "No" --> E["persist checkout + order"]
    E --> F["commit reserved inventory"]
```

## Future Payment Evolution

```mermaid
flowchart TD
    A["Confirm request"] --> B["Reconcile + price again"]
    B --> C["Reserve tracked inventory"]
    C --> D["Persist Checkout as PENDING_PAYMENT"]
    D --> E{"payment result"}
    E -- "Success" --> F["Create order"]
    F --> G["Commit inventory"]
    E -- "Fail or expire" --> H["Release inventory"]
    H --> I["Checkout -> EXPIRED or CANCELLED"]
```

## Read Model / API View

```mermaid
flowchart LR
    A["Checkout aggregate"] --> B["CheckoutMapper"]
    B --> C["CheckoutPreviewResponse"]
    B --> D["CheckoutConfirmationResponse"]
    B --> E["CheckoutSummaryResponse"]
    F["CartValidationOverview"] --> C
    G["Pricing result"] --> C
    A --> D
    A --> E
```
