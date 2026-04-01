# Order UML And Flow Diagrams

## Context And Boundaries

```mermaid
flowchart LR
    Checkout["Checkout domain\nimmutable commercial snapshot"] -->|CheckoutOrderFactory.buildOrder| Order["Order domain\ncommitted transaction"]
    Order -->|read by| Shipment["Shipment domain\ndelivery tracking"]
    Order -->|read by| Inventory["Inventory domain\nproduction flag"]
    Order -->|references| Address["Address domain\ndelivery address"]

    Customer["Customer\nrole: CUSTOMER"] -->|cancel| Order
    Seller["Seller\nrole: SELLER"] -->|confirm / process / complete / cancel| Order
    Admin["Admin\nrole: ADMIN"] -->|read| Order
```

---

## Class Diagram

```mermaid
classDiagram
    class Order {
        +Long id
        +Long version
        +String orderNumber
        +Long checkoutId
        +Long sourceCartId
        +Long customerId
        +Long sellerId
        +OrderStatus status
        +PaymentStatus paymentStatus
        +Address deliveryAddress
        +String deliveryUrlLocation
        +String deliveryNotes
        +String customerContactName
        +String customerContactPhone
        +boolean productionRequired
        +BigDecimal itemsTotal
        +BigDecimal shippingFee
        +BigDecimal discount
        +BigDecimal total
        +BigDecimal paidAmount
        +String cancelReason
        +Instant createdAt
        +Instant updatedAt
        +Instant confirmedAt
        +Instant completedAt
        +Instant cancelledAt
        +addItem()
        +markProductionRequired()
        +recomputeTotals()
        +confirm()
        +cancel()
        +complete()
    }

    class OrderItem {
        +Long id
        +Long productId
        +Long variantId
        +String productName
        +String variantName
        +OrderItemType type
        +BigDecimal unitPriceBase
        +BigDecimal unitPriceExtra
        +BigDecimal unitPrice
        +BigDecimal lineDiscount
        +BigDecimal lineTotal
        +Integer qtyOrdered
        +boolean allowBackorder
        +boolean productionRequired
        +Float preparationDays
        +markProductionRequired()
    }

    class OrderItemSelection {
        +Long id
        +Long attributeId
        +String attributeName
        +Long valueId
        +String valueText
        +BigDecimal extraPrice
    }

    class OrderStatus {
        CREATED
        CONFIRMED
        PROCESSING
        COMPLETED
        CUSTOMER_CANCELLED
        SELLER_CANCELLED
        +isTerminal()
        +isCancelled()
    }

    class PaymentStatus {
        NOT_PAID
        PARTIALLY_PAID
        PAID
    }

    class OrderItemType {
        STOCK
        PRE_ORDER
    }

    class Address {
        +Long id
        +String name
    }

    Order "1" *-- "0..*" OrderItem : items
    OrderItem "1" *-- "0..*" OrderItemSelection : selections
    Order --> OrderStatus
    Order --> PaymentStatus
    OrderItem --> OrderItemType
    Order --> Address : deliveryAddress
```

---

## Lifecycle State Machine

```mermaid
stateDiagram-v2
    [*] --> CREATED : CheckoutOrderFactory.buildOrder()

    CREATED --> CONFIRMED : seller confirmOrder()
    CONFIRMED --> PROCESSING : seller processOrder()
    PROCESSING --> COMPLETED : seller completeOrder()

    CREATED --> CUSTOMER_CANCELLED : customer cancelOrderByCustomer()
    CONFIRMED --> CUSTOMER_CANCELLED : customer cancelOrderByCustomer()
    PROCESSING --> CUSTOMER_CANCELLED : customer cancelOrderByCustomer()

    CREATED --> SELLER_CANCELLED : seller cancelOrderBySeller()
    CONFIRMED --> SELLER_CANCELLED : seller cancelOrderBySeller()
    PROCESSING --> SELLER_CANCELLED : seller cancelOrderBySeller()

    COMPLETED --> [*]
    CUSTOMER_CANCELLED --> [*]
    SELLER_CANCELLED --> [*]
```

---

## Order Creation Flow

```mermaid
sequenceDiagram
    participant CAS as CheckoutApplicationService
    participant COF as CheckoutOrderFactory
    participant OR as OrderRepository
    participant CR as CheckoutRepository

    CAS->>COF: buildOrder(checkout)
    COF->>COF: new Order()
    COF->>COF: set customerId, sellerId, deliveryAddress, contact, shippingFee, discount
    loop for each CheckoutItem
        COF->>COF: new OrderItem(productId, variantId, names, pricing, lineDiscount, qty, type)
        loop for each CheckoutItemSelection
            COF->>COF: new OrderItemSelection(attributeId, name, valueId, valueText, extraPrice)
        end
        COF->>COF: orderItem.addSelection(selection)
        COF->>COF: order.addItem(orderItem)
    end
    COF->>COF: order.recomputeTotals()
    COF-->>CAS: Order

    CAS->>CAS: order.setCheckoutId(checkout.getId())
    CAS->>OR: save(order)
    OR-->>CAS: savedOrder (with generated id and orderNumber)
    CAS->>CR: save(checkout.attachOrder(orderId, orderNumber))
```

---

## Customer Cancel Flow

```mermaid
sequenceDiagram
    participant C as Customer (REST)
    participant OC as OrderController
    participant OS as OrderService
    participant OR as OrderRepository

    C->>OC: POST /api/customer/orders/{orderId}/cancel
    OC->>OS: cancelOrderByCustomer(customerId, orderId, request)
    OS->>OR: lockByIdAndCustomerId(orderId, customerId)
    OR-->>OS: Order (PESSIMISTIC_WRITE lock)
    OS->>OS: ensureCancellable(order) - throws CONFLICT if terminal
    OS->>OS: order.cancel(CUSTOMER_CANCELLED, reason, now)
    OS->>OR: save(order)
    OC-->>C: 200 OK
```

---

## Seller Lifecycle Flow

```mermaid
sequenceDiagram
    participant S as Seller (REST)
    participant OC as OrderController
    participant OS as OrderService
    participant OR as OrderRepository

    S->>OC: POST /api/seller/orders/{orderId}/confirm
    OC->>OS: confirmOrder(sellerId, orderId)
    OS->>OR: lockById(orderId)
    OR-->>OS: Order (PESSIMISTIC_WRITE lock)
    OS->>OS: verify sellerId matches
    OS->>OS: verify status == CREATED
    OS->>OS: order.confirm(now)
    OS->>OR: save(order)
    OC-->>S: 200 OrderResponse

```

---

## Repository Query Map

```mermaid
flowchart TD
    subgraph OrderRepository
        LBI["lockById(id)\nPESSIMISTIC_WRITE"]
        LBIAC["lockByIdAndCustomerId(id, customerId)\nPESSIMISTIC_WRITE"]
        FBN["findByOrderNumber(number)"]
        FBIAC["findByIdAndCustomerId(id, customerId)"]
        FBIAS["findByIdAndSellerId(id, sellerId)"]
        FBCID["findByCustomerIdOrderByCreatedAtDesc(customerId)"]
        FBCIDS["findByCustomerIdAndStatusOrderByCreatedAtDesc(customerId, status)"]
        FBSID["findBySellerIdOrderByCreatedAtDesc(sellerId)"]
        FBSIDS["findBySellerIdAndStatusOrderByCreatedAtDesc(sellerId, status)"]
        SFA["searchForAdmin(filters)\nJPQL with nullable params"]
        FDDIAS["findOrderDetailsByIdAndSellerId(orderId, sellerId)\nJOIN FETCH items"]
    end

    OS_cancel["cancelOrderByCustomer"] --> LBIAC
    OS_seller["seller mutations"] --> LBI
    OS_getCust["getCustomerOrder"] --> FBIAC
    OS_getSeller["getSellerOrder"] --> FBIAS
    OS_listCust["listCustomerOrders"] --> FBCID
    OS_listCustF["listCustomerOrders + status"] --> FBCIDS
    OS_listSell["listSellerOrders"] --> FBSID
    OS_listSellF["listSellerOrders + status"] --> FBSIDS
    OS_admin["listAdminOrders"] --> SFA
    ShipmentService["ShipmentService.getSourceOrder"] --> FDDIAS
```
