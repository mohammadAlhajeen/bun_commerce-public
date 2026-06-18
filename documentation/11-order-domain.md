# Order Domain Reference

## Overview

The `Order` domain is the committed operational record produced from a confirmed `Checkout`.

It owns:

- the buyer and seller identity for the transaction
- the committed lifecycle state
- frozen delivery/contact snapshots copied from checkout
- frozen line-item and selection snapshots
- financial totals used by downstream fulfillment flows

Primary package:

- `com.bun.platform.order`

Collaborating packages:

- `com.bun.platform.checkout` - creates `Order` via `CheckoutOrderFactory`
- `com.bun.platform.shipment` - reads `Order` when creating a shipment
- `com.bun.platform.catalog.inventory` - may mark an order as production-required
- `com.bun.platform.address` - supplies normalized address data before checkout captures the order snapshot

Related diagrams: `documentation/11-order-uml.md`

---

## Architecture

`Order` is immutable with respect to commercial data once it is created. It is not rebuilt from live cart rows or live address entities.

| Concern | Owner |
| --- | --- |
| Pricing computation | `Checkout` |
| Inventory reservation | `Checkout` |
| Delivery address snapshot | `Order.deliveryAddress` (`OrderAddressSnapshot`) |
| Item details snapshot | `OrderItem` |
| Lifecycle transitions | `OrderService` |
| Shipment creation | `ShipmentService` |

`Order` is not:

- a live view over cart data
- a pricing engine
- an inventory aggregate
- a payment capture aggregate
- a shipment-tracking aggregate

Each order belongs to exactly one store and one customer.

---

## Domain Model

### `Order`

Aggregate root in `com.bun.platform.order`, persisted in `orders`.

Important fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `Long` | Primary key |
| `version` | `Long` | Optimistic lock version |
| `orderNumber` | `String` | Human-readable identifier |
| `checkoutId` | `Long` | Source checkout ID |
| `sourceCartId` | `Long` | Source cart ID |
| `customerId` | `Long` | Purchasing customer |
| `storeId` | `Long` | Owning store |
| `status` | `OrderStatus` | Fulfillment lifecycle state |
| `paymentStatus` | `PaymentStatus` | Payment lifecycle state |
| `deliveryAddress` | `OrderAddressSnapshot` | Frozen address snapshot captured at checkout time |
| `deliveryUrlLocation` | `String` | Optional map URL snapshot |
| `deliveryNotes` | `String` | Delivery instructions snapshot |
| `customerContactName` | `String` | Recipient name snapshot |
| `customerContactPhone` | `String` | Recipient phone snapshot |
| `productionRequired` | `boolean` | True if any line is a pre-order |
| `itemsTotal` | `BigDecimal` | Sum of line totals |
| `shippingFee` | `BigDecimal` | Shipping amount |
| `discount` | `BigDecimal` | Coupon discount total |
| `total` | `BigDecimal` | Grand total |
| `paidAmount` | `BigDecimal` | Amount paid so far |
| `cancelReason` | `String` | Optional cancellation reason |
| `createdAt` | `Instant` | Creation timestamp |
| `updatedAt` | `Instant` | Last update timestamp |
| `confirmedAt` | `Instant` | Seller confirmation timestamp |
| `completedAt` | `Instant` | Completion timestamp |
| `cancelledAt` | `Instant` | Cancellation timestamp |
| `items` | `List<OrderItem>` | Owned line items |

Domain methods:

- `addItem(item)` - attaches an item and propagates `productionRequired`
- `markProductionRequired()` - marks the order as requiring production
- `recomputeTotals()` - recalculates totals from line items
- `confirm(now)` - moves to `CONFIRMED`
- `cancel(status, reason, now)` - moves to a cancellation status
- `complete(now)` - moves to `COMPLETED`

### `OrderItem`

Child entity in `order_items`.

Important fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `Long` | Primary key |
| `order` | `Order` | Parent order |
| `productId` | `Long` | Product snapshot ID |
| `variantId` | `Long` | Variant snapshot ID |
| `productName` | `String` | Product snapshot name |
| `variantName` | `String` | Variant snapshot name |
| `type` | `OrderItemType` | `STOCK` or `PRE_ORDER` |
| `unitPriceBase` | `BigDecimal` | Base unit price from checkout |
| `unitPrice` | `BigDecimal` | Final unit price from checkout |
| `lineDiscount` | `BigDecimal` | Discount applied to the line |
| `lineTotal` | `BigDecimal` | Final line total |
| `qtyOrdered` | `Integer` | Ordered quantity |
| `selections` | `List<OrderItemSelection>` | Frozen selection snapshots |

Domain methods:

- `addSelection(selection)` - attaches a child selection
- `markAsPreOrder()` - flips the line to `PRE_ORDER`
- `requiresProduction()` - true when the line type is `PRE_ORDER`

### `OrderItemSelection`

Child entity in `order_item_selections`.

Fields:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `Long` | Primary key |
| `orderItem` | `OrderItem` | Parent line item |
| `attributeId` | `Long` | Attribute snapshot ID |
| `attributeName` | `String` | Attribute snapshot name |
| `valueId` | `Long` | Selected value ID |
| `valueText` | `String` | Selected value label/text |

---

## Enumerations

### `OrderStatus`

- `CREATED`
- `CONFIRMED`
- `PROCESSING`
- `COMPLETED`
- `CUSTOMER_CANCELLED`
- `SELLER_CANCELLED`

Helpers:

- `isTerminal()` -> completed or cancelled states
- `isCancelled()` -> cancellation states

### `PaymentStatus`

- `NOT_PAID`
- `PARTIALLY_PAID`
- `PAID`

### `OrderItemType`

- `STOCK`
- `PRE_ORDER`

---

## Services

### `OrderService`

Application service in `com.bun.platform.order.services`.

Customer operations:

- `listCustomerOrders(customerId, status)`
- `getCustomerOrder(customerId, orderId)`
- `cancelOrderByCustomer(customerId, orderId, request)`

Seller operations:

- `listSellerOrders(storeId, status)`
- `getSellerOrder(storeId, orderId)`
- `confirmOrder(storeId, orderId)`
- `contactOrder(storeId, orderId)`
- `markOrderPaidBySeller(storeId, orderId)`
- `cancelOrderBySeller(storeId, orderId, request)`

Admin operations:

- `listAdminOrders(storeId, customerId, status)`
- `getAdminOrder(orderId)`

---

## REST API

### Customer endpoints

- `GET /api/customer/orders`
- `GET /api/customer/orders/{orderId}`
- `POST /api/customer/orders/{orderId}/cancel`

### Seller endpoints

All seller endpoints require `?storeId={storeId}` query parameter.

- `GET /api/seller/orders`
- `GET /api/seller/orders/{orderId}`
- `POST /api/seller/orders/{orderId}/confirm`
- `POST /api/seller/orders/{orderId}/contact`
- `POST /api/seller/orders/{orderId}/mark-paid`
- `POST /api/seller/orders/{orderId}/cancel`

### Admin endpoints

- `GET /api/admin/orders`
- `GET /api/admin/orders/{orderId}`

---

## DTOs

### `OrderResponse`

Fields:

- `id`, `orderNumber`, `checkoutId`, `sourceCartId`
- `customerId`, `storeId`
- `status`, `paymentStatus`, `productionRequired`
- `deliveryAddressId`, `deliveryAddressName`, `deliveryUrlLocation`, `deliveryNotes`

`deliveryAddressId` and `deliveryAddressName` in the API are projected from the embedded `OrderAddressSnapshot`.
- `customerContactName`, `customerContactPhone`
- `itemsTotal`, `shippingFee`, `discount`, `total`, `paidAmount`
- `cancelReason`
- `createdAt`, `updatedAt`, `confirmedAt`, `completedAt`, `cancelledAt`
- `version`
- `items`

### `OrderSummaryResponse`

Fields:

- `id`, `orderNumber`
- `customerId`, `storeId`
- `status`, `paymentStatus`
- `customerContactName`, `customerContactPhone`
- `itemsTotal`, `shippingFee`, `discount`, `total`
- `createdAt`, `updatedAt`

### `OrderItemResponse`

Fields:

- `id`, `productId`, `variantId`
- `productName`, `variantName`
- `type`
- `unitPriceBase`, `unitPrice`
- `lineDiscount`, `lineTotal`
- `qtyOrdered`
- `selections`

### `OrderItemSelectionResponse`

Fields:

- `id`, `attributeId`, `attributeName`, `valueId`, `valueText`

### `CancelOrderRequest`

Fields:

- `reason`

---

## Order Creation Flow

`Order` is created only from checkout confirmation:

```text
CheckoutApplicationService.confirmCheckout()
  -> CheckoutOrderFactory.buildOrder(checkout)
      -> copy checkout identity, delivery snapshot, contact snapshot, and totals
      -> create one OrderItem per CheckoutItem
      -> create one OrderItemSelection per CheckoutItemSelection
      -> recompute order totals
  -> orderRepository.save(order)
  -> checkout.attachOrder(orderId, orderNumber)
```

---

## Lifecycle

```text
CREATED -> CONFIRMED -> PROCESSING -> COMPLETED
   |           |             |
   +--------> CUSTOMER_CANCELLED
   +--------> SELLER_CANCELLED
```

Terminal states:

- `COMPLETED`
- `CUSTOMER_CANCELLED`
- `SELLER_CANCELLED`

---

## Concurrency

All write operations use pessimistic write locking on the `Order` row.

- `lockById(id)` for seller/admin mutations
- `lockByIdAndCustomerId(id, customerId)` for customer cancellation

`Order.version` provides optimistic locking protection for out-of-band updates.
