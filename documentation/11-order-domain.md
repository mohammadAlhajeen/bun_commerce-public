# Order Domain Reference

## Overview

The `Order` domain represents the committed business transaction produced from a confirmed `Checkout`.

It is responsible for:

- recording what was purchased, from whom, and by whom
- tracking order lifecycle from creation through completion or cancellation
- storing a frozen snapshot of delivery address, contact, and item details at the time of purchase
- exposing lifecycle transition operations to sellers and cancellation operations to customers
- providing scoped read access for customers, sellers, and admins

Primary package:

- `com.bun.platform.order`

Collaborating packages:

- `com.bun.platform.checkout` — creates `Order` via `CheckoutOrderFactory`
- `com.bun.platform.shipment` — reads `Order` when creating a shipment
- `com.bun.platform.catalog.inventory` — marks `OrderItem` as production-required
- `com.bun.platform.address` — stores a reference to the delivery `Address`

Related diagrams: `documentation/11-order-uml.md`

---

## 1. Architectural Interpretation

### Core interpretation

`Order` is an immutable business record once created. It is never rebuilt from live cart or checkout data. It is created once by `CheckoutApplicationService` via `CheckoutOrderFactory`, and from that point forward it is only transitioned through its own lifecycle.

| Concern                       | Owner                                         |
| ----------------------------- | --------------------------------------------- |
| Pricing computation           | `Checkout` (before order creation)            |
| Inventory reservation         | `Checkout` (before order creation)            |
| Delivery address snapshot ref | `Order.deliveryAddress` (`Address` ManyToOne) |
| Item details snapshot         | `OrderItem` (frozen at creation)              |
| Lifecycle transitions         | `OrderService`                                |
| Shipment creation             | `ShipmentService` (reads from `Order`)        |

### What Order is not

`Order` is not:

- a live view over `Cart` items
- a mutable pricing record
- responsible for inventory
- responsible for payment capture
- responsible for shipment tracking

### Single-seller scope

Each `Order` belongs to exactly one seller and one customer.  
Cross-seller scenarios must be handled above this domain.

---

## 2. Domain Model

### Aggregate root: `Order`

`Order` is the aggregate root. It owns:

- order identity and number
- references to the originating checkout and cart
- customer and seller identity
- delivery address reference and contact snapshot
- financial totals (items total, shipping fee, discount, grand total, paid amount)
- lifecycle status and payment status
- cancellation metadata
- all `OrderItem` children (CASCADE ALL)

### Child entity: `OrderItem`

`OrderItem` is not an aggregate root.

It stores a frozen snapshot of a purchased line item:

- product and variant identity
- product and variant names (snapshot, not live catalog reference)
- pricing breakdown (unit base price, unit extra, unit price, line discount, line total)
- quantity ordered
- backorder and production flags
- preparation days
- attribute selections (`OrderItemSelection`)

### Child entity: `OrderItemSelection`

`OrderItemSelection` is not an aggregate root.

It stores one attribute selection chosen for the parent `OrderItem`:

- attribute id and name
- value id and text
- extra price contribution

---

## 3. Type Reference

### `Order`

**Kind:** aggregate root entity  
**Package:** `com.bun.platform.order`  
**Table:** `orders`

#### Fields

| Field                  | Type              | Description                                           |
| ---------------------- | ----------------- | ----------------------------------------------------- |
| `id`                   | `Long`            | Primary key                                           |
| `version`              | `Long`            | Optimistic lock version                               |
| `orderNumber`          | `String`          | Unique human-readable identifier (`ORD-XXXXXXXXXXXX`) |
| `checkoutId`           | `Long`            | ID of the `Checkout` that produced this order         |
| `sourceCartId`         | `Long`            | ID of the original `Cart`                             |
| `customerId`           | `Long`            | Identity of the purchasing customer                   |
| `sellerId`             | `Long`            | Identity of the selling party                         |
| `status`               | `OrderStatus`     | Current lifecycle state                               |
| `paymentStatus`        | `PaymentStatus`   | Current payment state                                 |
| `deliveryAddress`      | `Address`         | ManyToOne reference to the delivery address           |
| `deliveryUrlLocation`  | `String`          | Optional GPS/map URL for delivery                     |
| `deliveryNotes`        | `String`          | Optional delivery instructions                        |
| `customerContactName`  | `String`          | Contact name snapshot                                 |
| `customerContactPhone` | `String`          | Contact phone snapshot                                |
| `productionRequired`   | `boolean`         | True if any item requires production                  |
| `itemsTotal`           | `BigDecimal`      | Sum of all item line totals                           |
| `shippingFee`          | `BigDecimal`      | Shipping cost                                         |
| `discount`             | `BigDecimal`      | Total discount applied                                |
| `total`                | `BigDecimal`      | Grand total (`itemsTotal + shippingFee - discount`)   |
| `paidAmount`           | `BigDecimal`      | Amount paid so far                                    |
| `cancelReason`         | `String`          | Optional cancellation reason                          |
| `createdAt`            | `Instant`         | Set on first persist                                  |
| `updatedAt`            | `Instant`         | Set on every update                                   |
| `confirmedAt`          | `Instant`         | When seller confirmed                                 |
| `completedAt`          | `Instant`         | When order completed                                  |
| `cancelledAt`          | `Instant`         | When order was cancelled                              |
| `items`                | `List<OrderItem>` | Line items (OneToMany, CASCADE ALL)                   |

#### Domain methods

| Method                        | Description                                                   |
| ----------------------------- | ------------------------------------------------------------- |
| `addItem(item)`               | Adds an item and propagates `productionRequired` flag         |
| `markProductionRequired()`    | Manually flags order as production-required                   |
| `recomputeTotals()`           | Recalculates `itemsTotal` and `total` from items              |
| `confirm(now)`                | Transitions to `CONFIRMED`, sets `confirmedAt`                |
| `cancel(status, reason, now)` | Transitions to a cancel status, sets reason and `cancelledAt` |
| `complete(now)`               | Transitions to `COMPLETED`, sets `completedAt`                |

---

### `OrderItem`

**Kind:** child entity  
**Package:** `com.bun.platform.order`  
**Table:** `order_items`

#### Fields

| Field                | Type                       | Description                                                        |
| -------------------- | -------------------------- | ------------------------------------------------------------------ |
| `id`                 | `Long`                     | Primary key                                                        |
| `order`              | `Order`                    | Parent order (ManyToOne)                                           |
| `productId`          | `Long`                     | Catalog product ID snapshot                                        |
| `variantId`          | `Long`                     | Catalog variant ID snapshot (nullable for single-variant products) |
| `productName`        | `String`                   | Product name snapshot                                              |
| `variantName`        | `String`                   | Variant name snapshot                                              |
| `type`               | `OrderItemType`            | `STOCK` or `PRE_ORDER`                                             |
| `unitPriceBase`      | `BigDecimal`               | Base price from the variant                                        |
| `unitPriceExtra`     | `BigDecimal`               | Extra price from attribute selections                              |
| `unitPrice`          | `BigDecimal`               | Final unit price (`base + extra`)                                  |
| `lineDiscount`       | `BigDecimal`               | Discount applied to this line                                      |
| `lineTotal`          | `BigDecimal`               | Final line total (`unitPrice × qty - lineDiscount`)                |
| `qtyOrdered`         | `Integer`                  | Quantity ordered                                                   |
| `allowBackorder`     | `boolean`                  | Whether backorder was allowed                                      |
| `productionRequired` | `boolean`                  | Whether item needs manufacturing                                   |
| `preparationDays`    | `Float`                    | Expected preparation time in days                                  |
| `selections`         | `List<OrderItemSelection>` | Attribute selections (OneToMany, CASCADE ALL)                      |

#### Domain methods

| Method                     | Description                             |
| -------------------------- | --------------------------------------- |
| `markProductionRequired()` | Flags this item as requiring production |

---

### `OrderItemSelection`

**Kind:** child entity  
**Package:** `com.bun.platform.order`  
**Table:** `order_item_selections`

#### Fields

| Field           | Type         | Description                                        |
| --------------- | ------------ | -------------------------------------------------- |
| `id`            | `Long`       | Primary key                                        |
| `orderItem`     | `OrderItem`  | Parent item (ManyToOne)                            |
| `attributeId`   | `Long`       | Catalog attribute ID                               |
| `attributeName` | `String`     | Attribute name snapshot                            |
| `valueId`       | `Long`       | Attribute value ID (nullable for free-text values) |
| `valueText`     | `String`     | Selected value text snapshot                       |
| `extraPrice`    | `BigDecimal` | Price contribution from this selection             |

---

## 4. Enumerations

### `OrderStatus`

| Value                | Description                                                |
| -------------------- | ---------------------------------------------------------- |
| `CREATED`            | Freshly created by checkout. Awaiting seller confirmation. |
| `CONFIRMED`          | Seller accepted the order and is preparing it.             |
| `PROCESSING`         | Items are being processed or packed.                       |
| `COMPLETED`          | Order fully delivered and closed.                          |
| `CUSTOMER_CANCELLED` | Cancelled by the customer.                                 |
| `SELLER_CANCELLED`   | Cancelled by the seller.                                   |

Helper predicates:

| Method          | Returns `true` for                                    |
| --------------- | ----------------------------------------------------- |
| `isTerminal()`  | `COMPLETED`, `CUSTOMER_CANCELLED`, `SELLER_CANCELLED` |
| `isCancelled()` | `CUSTOMER_CANCELLED`, `SELLER_CANCELLED`              |

### `PaymentStatus`

| Value            | Description               |
| ---------------- | ------------------------- |
| `NOT_PAID`       | No payment received yet.  |
| `PARTIALLY_PAID` | Partial payment received. |
| `PAID`           | Order fully paid.         |

### `OrderItemType`

| Value       | Description                                                   |
| ----------- | ------------------------------------------------------------- |
| `STOCK`     | Item fulfilled from existing inventory (in-stock product).    |
| `PRE_ORDER` | Item requires manufacturing or preparation before fulfilment. |

---

## 5. Services

### `OrderService`

**Package:** `com.bun.platform.order.services`

Central application service containing all order use cases. Organized into three scopes:

#### Customer operations

| Method                                                | Description                                                                                       |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `listCustomerOrders(customerId, status)`              | Returns summary list of all orders belonging to the customer, optionally filtered by status.      |
| `getCustomerOrder(customerId, orderId)`               | Returns full order detail. Throws `ORDER_NOT_FOUND` if the order does not belong to the customer. |
| `cancelOrderByCustomer(customerId, orderId, request)` | Cancels a non-terminal order as `CUSTOMER_CANCELLED`. Uses pessimistic write lock.                |

#### Seller operations

| Method                                            | Description                                                                                |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `listSellerOrders(sellerId, status)`              | Returns summary list of all orders for the seller, optionally filtered by status.          |
| `getSellerOrder(sellerId, orderId)`               | Returns full order detail. Throws `ORDER_NOT_FOUND` if order does not belong to seller.    |
| `confirmOrder(sellerId, orderId)`                 | Transitions `CREATED → CONFIRMED`. Throws `ORDER_CONFLICT` if not in `CREATED` state.      |
| `processOrder(sellerId, orderId)`                 | Transitions `CONFIRMED → PROCESSING`. Throws `ORDER_CONFLICT` if not in `CONFIRMED` state. |
| `completeOrder(sellerId, orderId)`                | Transitions any non-terminal, non-cancelled order to `COMPLETED`.                          |
| `cancelOrderBySeller(sellerId, orderId, request)` | Cancels a non-terminal order as `SELLER_CANCELLED`.                                        |

#### Admin operations

| Method                                          | Description                                                   |
| ----------------------------------------------- | ------------------------------------------------------------- |
| `listAdminOrders(sellerId, customerId, status)` | Cross-seller/customer search with all three filters nullable. |
| `getAdminOrder(orderId)`                        | Returns full order detail by ID without ownership check.      |

---

## 6. REST API

### `OrderController`

**Package:** `com.bun.platform.order.controllers`  
**Security:** JWT bearer token; role-based authorization via `@PreAuthorize`

#### Customer endpoints

| Method | Path                                    | Role       | Description                                         |
| ------ | --------------------------------------- | ---------- | --------------------------------------------------- |
| `GET`  | `/api/customer/orders`                  | `CUSTOMER` | List orders. Optional `?status=` filter.            |
| `GET`  | `/api/customer/orders/{orderId}`        | `CUSTOMER` | Get full order detail.                              |
| `POST` | `/api/customer/orders/{orderId}/cancel` | `CUSTOMER` | Cancel order. Optional body: `{ "reason": "..." }`. |

#### Seller endpoints

| Method | Path                                    | Role     | Description                                         |
| ------ | --------------------------------------- | -------- | --------------------------------------------------- |
| `GET`  | `/api/seller/orders`                    | `SELLER` | List orders. Optional `?status=` filter.            |
| `GET`  | `/api/seller/orders/{orderId}`          | `SELLER` | Get full order detail.                              |
| `POST` | `/api/seller/orders/{orderId}/confirm`  | `SELLER` | Confirm order (`CREATED → CONFIRMED`).              |
| `POST` | `/api/seller/orders/{orderId}/process`  | `SELLER` | Move to processing (`CONFIRMED → PROCESSING`).      |
| `POST` | `/api/seller/orders/{orderId}/complete` | `SELLER` | Complete order.                                     |
| `POST` | `/api/seller/orders/{orderId}/cancel`   | `SELLER` | Cancel order. Optional body: `{ "reason": "..." }`. |

#### Admin endpoints

| Method | Path                          | Role    | Description                                                           |
| ------ | ----------------------------- | ------- | --------------------------------------------------------------------- |
| `GET`  | `/api/admin/orders`           | `ADMIN` | Search all orders. Optional `?sellerId=`, `?customerId=`, `?status=`. |
| `GET`  | `/api/admin/orders/{orderId}` | `ADMIN` | Get full order detail.                                                |

---

## 7. DTOs

### `OrderResponse`

Full order detail returned by single-order endpoints.

Fields: `id`, `orderNumber`, `checkoutId`, `sourceCartId`, `customerId`, `sellerId`, `status`, `paymentStatus`, `productionRequired`, `deliveryAddressId`, `deliveryAddressName`, `deliveryUrlLocation`, `deliveryNotes`, `customerContactName`, `customerContactPhone`, `itemsTotal`, `shippingFee`, `discount`, `total`, `paidAmount`, `cancelReason`, `createdAt`, `updatedAt`, `confirmedAt`, `completedAt`, `cancelledAt`, `version`, `List<OrderItemResponse> items`

### `OrderSummaryResponse`

Slim view returned by list endpoints.

Fields: `id`, `orderNumber`, `customerId`, `sellerId`, `status`, `paymentStatus`, `customerContactName`, `customerContactPhone`, `itemsTotal`, `shippingFee`, `discount`, `total`, `createdAt`, `updatedAt`

### `OrderItemResponse`

Per-item detail embedded in `OrderResponse`.

Fields: `id`, `productId`, `variantId`, `productName`, `variantName`, `type`, `unitPriceBase`, `unitPriceExtra`, `unitPrice`, `lineDiscount`, `lineTotal`, `qtyOrdered`, `allowBackorder`, `productionRequired`, `preparationDays`, `List<OrderItemSelectionResponse> selections`

### `OrderItemSelectionResponse`

Per-selection detail embedded in `OrderItemResponse`.

Fields: `id`, `attributeId`, `attributeName`, `valueId`, `valueText`, `extraPrice`

### `CancelOrderRequest`

Request body for cancel endpoints (optional body).

Fields: `reason` (String, max 512 characters)

---

## 8. Exceptions

### `OrderException`

**Package:** `com.bun.platform.exception`  
**Extends:** `DomainApiException`

| Factory method    | HTTP status | Error code          | When thrown                                  |
| ----------------- | ----------- | ------------------- | -------------------------------------------- |
| `notFound(msg)`   | 404         | `ORDER_NOT_FOUND`   | Order not found or does not belong to caller |
| `conflict(msg)`   | 409         | `ORDER_CONFLICT`    | Illegal state transition attempted           |
| `forbidden(msg)`  | 403         | `ORDER_FORBIDDEN`   | Caller does not own the order                |
| `validation(msg)` | 400         | `ORDER_BAD_REQUEST` | Invalid request parameter                    |

---

## 9. Order Creation Flow

`Order` is never created through the `OrderController`. It is always created by the checkout domain:

```
CheckoutApplicationService.confirmCheckout()
  └─ CheckoutOrderFactory.buildOrder(checkout)
       ├─ new Order()                         // populate fields from Checkout snapshot
       ├─ order.setCheckoutId(checkout.getId())
       ├─ order.setSourceCartId(checkout.getSourceCartId())
       ├─ for each CheckoutItem → new OrderItem()
       │     ├─ setProductId / setVariantId
       │     ├─ setProductName / setVariantName
       │     ├─ setPricing / setLineDiscount / setLineTotal
       │     └─ for each selection → new OrderItemSelection()
       └─ order.recomputeTotals()
  └─ orderRepository.save(order)
  └─ checkout.attachOrder(order.getId(), order.getOrderNumber())
```

---

## 10. Lifecycle State Machine

```
CREATED ──► CONFIRMED ──► PROCESSING ──► COMPLETED
   │              │              │
   ▼              ▼              ▼
CUSTOMER_CANCELLED / SELLER_CANCELLED
```

- `CREATED → CONFIRMED`: seller calls `confirmOrder`
- `CONFIRMED → PROCESSING`: seller calls `processOrder`
- `PROCESSING → COMPLETED`: seller calls `completeOrder`
- Any non-terminal state → `CUSTOMER_CANCELLED`: customer calls `cancelOrderByCustomer`
- Any non-terminal state → `SELLER_CANCELLED`: seller calls `cancelOrderBySeller`
- `COMPLETED`, `CUSTOMER_CANCELLED`, `SELLER_CANCELLED` are terminal — no further transitions allowed

---

## 11. Concurrency

All write operations use pessimistic write locking (`LockModeType.PESSIMISTIC_WRITE`) on the `Order` row.

- `lockById(id)` — used for seller and admin mutations
- `lockByIdAndCustomerId(id, customerId)` — used for customer cancellation

`Order` also carries an optimistic lock `@Version` field that guards against concurrent out-of-band updates.
