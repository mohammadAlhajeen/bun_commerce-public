# Checkout Domain

## Goal

This module introduces a dedicated `Checkout` domain between `Cart` and `Order`.

It exists to solve a specific commerce problem:

- `Cart` is mutable and continuously repaired against live product and inventory state.
- `Order` is a committed business transaction and should not depend on the live cart at commit time.
- a customer still needs a final commercial confirmation step that freezes:
  - what they are buying
  - where it will be delivered
  - who will receive it
  - what the final totals were
  - what coupon and shipping result were used

That frozen commercial intent is the responsibility of `Checkout`.

Related diagrams: `documentation/10-checkout-uml.md`

## 1. Architectural Interpretation

### Core interpretation

- `Cart` is the mutable shopping workspace.
- `Checkout` is the immutable commercial snapshot created only when the customer confirms.
- `Order` is the committed operational transaction created from the checkout snapshot.

This means the system now has three distinct concepts with different lifecycles:

| Concept | Nature | Persistence timing | Owns live state? |
|--------|--------|--------------------|------------------|
| `Cart` | mutable shopping intent | throughout shopping | yes |
| `Checkout` | immutable commercial confirmation snapshot | only at confirm | no |
| `Order` | committed business transaction | after confirm succeeds | no |

### What checkout is not

Checkout is not:

- a live view over cart rows
- a pricing engine
- an inventory aggregate
- a replacement for order
- a draft entity saved on every address or coupon edit

### Single-seller scope

The current implementation is intentionally single-cart and single-seller.

That matches the existing cart model:

- one cart is scoped to one seller
- one checkout confirms one cart
- one order is produced from one checkout

Cross-seller orchestration can be added later above this module, but it should not be pushed into this aggregate.

## 2. Recommended Domain Model

### Aggregate root: `Checkout`

`Checkout` is the aggregate root because it is the smallest consistency boundary that must hold together at confirm time.

It owns:

- checkout identity
- checkout status
- source cart reference
- customer and seller ids
- address snapshot
- contact snapshot
- delivery notes snapshot
- coupon outcome snapshot
- shipping method snapshot
- totals snapshot
- reservation timestamps
- created order linkage
- checkout items

Code:

- `com.bun.platform.checkout.domain.Checkout`

### Child entity: `CheckoutItem`

`CheckoutItem` is not an aggregate root.

It exists only inside `Checkout` and stores:

- source cart item id
- variant id
- product id
- product name
- variant name
- inventory policy snapshot
- variant purchase version snapshot
- quantity
- unit prices
- line subtotal / discount / final total
- item selections

Code:

- `com.bun.platform.checkout.domain.CheckoutItem`

### Child entity: `CheckoutItemSelection`

`CheckoutItemSelection` stores the selected option snapshot used at confirm time.

It exists so the checkout can preserve:

- attribute id
- attribute name
- selected value id
- selected value text

Code:

- `com.bun.platform.checkout.domain.CheckoutItemSelection`

### Value objects / snapshots

#### `CheckoutAddressSnapshot`

Stores the delivery address as immutable commercial data:

- customer address linkage
- normalized address ids
- address text fragments
- building / apartment / floor / additional info
- address phone
- latitude / longitude

Code:

- `com.bun.platform.checkout.snapshot.CheckoutAddressSnapshot`

#### `CheckoutContactSnapshot`

Stores the final receiving contact:

- recipient name
- recipient phone

Code:

- `com.bun.platform.checkout.snapshot.CheckoutContactSnapshot`

### Pricing result model

Pricing is not embedded as rules inside the aggregate.

Instead, the aggregate stores the result of pricing:

- subtotal amount
- item discount total
- shipping total
- coupon discount total
- grand total
- shipping method code / label
- coupon applied flag / description

The calculation itself lives in:

- `CheckoutPricingService`
- `CheckoutShippingService`
- `CheckoutCouponService`

### Reservation metadata

Checkout stores reservation metadata for future payment and expiration support:

- `inventoryReservedAt`
- `inventoryReservationExpiresAt`
- `expiresAt`

These fields are intentionally included now even though current confirm goes directly to order creation.

## 3. Aggregate Boundaries And Invariants

### Why `Checkout` should be an aggregate root

`Checkout` should be an aggregate root because the following invariants must change together:

- all checkout items belong to exactly one checkout
- all checkout totals correspond to those items
- the address/contact snapshot corresponds to the same confirmation
- the order linkage belongs to the same committed confirmation
- the lifecycle state applies to the whole confirmation, not to individual lines

If `CheckoutItem` were independent, the model would allow partial mutation of a confirmed snapshot, which is precisely what checkout must prevent.

### Aggregate invariants

`Checkout` must satisfy:

- checkout items are snapshot data only
- no live `CartItem` or `Cart` entities are navigated after persistence
- totals are the frozen result of the pricing service at confirm time
- checkout belongs to one customer and one seller
- all items belong to the same seller-scoped cart
- checkout can be linked to at most one resulting order
- checkout lifecycle changes apply at aggregate level

### What belongs outside the aggregate

#### Outside `Checkout`, in `Cart`

- mutable quantity changes
- item add/remove
- acknowledgment flows
- reconcile repair logic

#### Outside `Checkout`, in `Pricing`

- shipping calculation rules
- coupon validation rules
- future tax rules
- promotion policy logic

#### Outside `Checkout`, in `Inventory`

- actual stock truth
- reserve / release / commit behavior
- oversell prevention

#### Outside `Checkout`, in `Order`

- fulfillment lifecycle
- shipment creation
- payment capture / settlement
- merchant operational workflow

## 4. Checkout Lifecycle / State Design

### Persisted states

The current persisted lifecycle is intentionally small:

- `ORDER_CREATED`
- `EXPIRED`
- `CANCELLED`

Deferred but already modeled:

- `PENDING_PAYMENT`

Code:

- `com.bun.platform.checkout.domain.CheckoutStatus`

### Why `PREVIEWED` is not persisted

`PREVIEWED` is not a useful persisted state because preview is stateless.

When the user:

- opens checkout
- changes address
- changes coupon
- recalculates totals

the system should not create or mutate checkout rows.

Persisting `PREVIEWED` would create write amplification and stale draft rows with no business value.

### Why `FAILED` is not persisted

`FAILED` is also intentionally not persisted in the current design.

If confirm fails during:

- re-reconcile
- pricing
- reservation
- order creation

the whole transaction should roll back. A failed attempt is an application event, not a durable business object.

### Current transition model

Current effective transition:

- no row -> `ORDER_CREATED`

Future transitions:

- `PENDING_PAYMENT` -> `ORDER_CREATED`
- `PENDING_PAYMENT` -> `EXPIRED`
- `PENDING_PAYMENT` -> `CANCELLED`

## 5. Pricing Integration Design

### Principle

Pricing before confirm must remain stateless.

That means:

- preview calls pricing directly
- address edits do not create checkout rows
- coupon edits do not create checkout rows
- checkout entity does not perform pricing logic internally

### Current pricing service shape

The module uses:

- `CheckoutPricingRequest`
- `CheckoutPricingSourceLine`
- `CheckoutPricingResult`
- `CheckoutPricingLine`

Code:

- `com.bun.platform.checkout.service.CheckoutPricingService`
- `com.bun.platform.checkout.service.CheckoutPricingService`

### Pricing inputs

Pricing consumes:

- customer id
- seller id
- resolved shipping address snapshot
- optional coupon code
- reconciled cart line data:
  - cart item id
  - variant id
  - quantity
  - unit base price
  - unit discount
  - unit final price

Important detail:

pricing starts from already reconciled cart prices. It does not attempt to replace cart reconciliation.

### Shipping integration

Shipping is delegated to `CheckoutShippingService`.

Current behavior:

- configurable flat-rate shipping
- no reservation
- no carrier coupling

Future behavior can plug in:

- seller delivery policy
- address-based quotes
- geo pricing
- shipping method selection

### Coupon integration

Coupon evaluation is delegated to `CheckoutCouponService`.

Current behavior:

- empty coupon code means no coupon
- non-empty coupon code is rejected by the default stub implementation

This is deliberate. The extension point exists without faking a coupon domain that is not implemented yet.

### What checkout stores from pricing

Checkout stores only the result:

- line prices
- shipping method + amount
- coupon outcome
- totals

Checkout does not store executable pricing rules.

## 6. Inventory Reservation Integration Design

### Principle

Reservation happens only when the customer confirms.

Never during:

- preview
- address changes
- coupon changes
- intermediate pricing refresh

### Current reservation mechanism

The module uses the existing inventory mutation primitives:

- atomic SQL reserve
- atomic SQL commit
- atomic SQL release

Through:

- `InventoryReservationService`
- `InventoryReservationService`

Which delegates to:

- `InventoryService.reserveTrackedStock`
- `InventoryService.commitTrackedStock`
- `InventoryService.releaseTrackedStock`

### Transaction boundary

Confirm runs in one Spring transaction inside `CheckoutApplicationService.confirmCheckout(...)`.

The sequence is:

1. lock cart
2. run `validateCartForReconcile` again
3. resolve address/contact snapshot
4. recalculate pricing again
5. reserve tracked inventory
6. persist checkout snapshot
7. create order
8. update checkout with created order id / order number
9. commit reserved inventory
10. close cart

### Why reserve before persisting checkout

Reservation happens before checkout persistence because the reservation is part of the commit precondition.

If stock cannot be reserved:

- no checkout should be written
- no order should be written

This preserves the invariant that a persisted checkout represents a commercially confirmable state.

### Why commit inventory in the same transaction

Current confirm creates the order immediately and there is no payment wait state.

So the cleanest current behavior is:

- reserve first to detect contention safely
- create checkout and order
- commit stock in the same transaction

That keeps:

- no overselling
- no leaked reserved stock
- no background compensator requirement for the current flow

### Future release strategy

When payment is introduced, the transition changes:

- reserve inventory
- persist checkout in `PENDING_PAYMENT`
- do not commit stock yet
- release on payment expiration / cancellation
- commit on payment success

The aggregate already carries reservation timestamps to support that future.

## 7. Application Service Flow

### `prepareCheckoutPreview`

Main orchestration lives in:

- `CheckoutApplicationService.prepareCheckoutPreview(...)`

Flow:

1. load and lock the customer cart
2. run `validateCartForReconcile(cartId)`
3. resolve saved address plus receiver contact into snapshots
4. build `CheckoutPricingRequest`
5. call pricing service
6. return preview DTO

Properties:

- no checkout row is persisted
- no reservation is created
- no order is created
- no cart is closed

### `confirmCheckout`

Main orchestration lives in:

- `CheckoutApplicationService.confirmCheckout(...)`

Flow:

1. load and lock the customer cart
2. run `validateCartForReconcile(cartId)` again
3. resolve address/contact again
4. price again
5. reject if cart has blocking reconcile issues
6. reject if the cart became empty
7. reject if coupon was rejected
8. load full variant projections for the surviving lines
9. reserve tracked inventory
10. build immutable checkout snapshot
11. persist checkout
12. build order from checkout snapshot
13. persist order
14. update checkout with order linkage
15. commit reserved inventory
16. close cart

### Failure behavior

Because confirm is one transaction:

- reconcile failure means nothing is persisted
- pricing failure means nothing is persisted
- reservation failure means nothing is persisted
- order creation failure means reservation and checkout persistence roll back

This is the correct default for the current direct-to-order flow.

## 8. DTO / API Shape

### Current endpoints

| Method | Path | Purpose |
|--------|------|---------|
| `POST` | `/api/checkouts/preview` | Stateless preview |
| `POST` | `/api/checkouts/confirm` | Final confirmation |
| `GET` | `/api/checkouts/{checkoutId}` | Snapshot summary |

### Preview request

`CheckoutPreviewRequest`

Fields:

- `cartId`
- `appUserAddressId`
- `recipientName`
- `recipientPhone`
- `deliveryNotes`
- `couponCode`

### Preview response

`CheckoutPreviewResponse`

Contains:

- cart identity
- seller identity
- `confirmable` flag
- shipping address snapshot view
- contact snapshot view
- shipping view
- coupon outcome view
- pricing totals view
- checkout item views
- original cart validation overview

### Confirm request

`CheckoutConfirmRequest`

It intentionally mirrors preview request because confirm must re-evaluate all final commercial inputs.

### Confirm response

`CheckoutConfirmationResponse`

Contains:

- checkout id / number
- checkout status
- order id / number
- source cart id
- created at
- snapshot address/contact
- shipping / coupon / totals
- snapshot items

### Summary response

`CheckoutSummaryResponse`

Adds:

- customer id
- seller id
- delivery notes
- expiration metadata
- reservation metadata

## 9. Suggested Code Structure

Current package structure:

- `checkout.domain`
- `checkout.snapshot`
- `checkout.service`
- `checkout.application`
- `checkout.dto`
- `checkout.mapper`
- `checkout.repository`
- `checkout.controller`
- `checkout.exception`

### Responsibility split

#### `domain`

Owns entities and aggregate lifecycle.

#### `snapshot`

Owns embedded immutable commercial value objects.

#### `service`

Owns stateless integration contracts:

- pricing
- shipping
- coupon
- reservation
- input resolution

#### `application`

Owns orchestration and transaction boundaries:

- `CheckoutApplicationService`
- `CheckoutOrderFactory`

#### `dto`

Owns transport contracts for frontend-facing APIs.

#### `mapper`

Owns DTO projection assembly.

## 10. Important Implementation Notes

### `CheckoutInputResolver`

This component turns mutable customer profile data into immutable checkout snapshot data.

It resolves:

- ownership of the selected saved address
- fallback recipient name
- fallback recipient phone
- normalized address snapshot

### `CheckoutOrderFactory`

This component creates:

- `Checkout` from prepared commercial input
- `Order` from persisted checkout snapshot

This keeps order-creation details out of the application service and makes future payment transitions easier to refactor.

### `CheckoutMapper`

This mapper exposes a frontend-friendly API without leaking persistence structure directly.

It keeps preview and persisted-summary shapes aligned.

### `CheckoutProperties`

This configuration object already supports:

- reservation TTL
- shipping defaults

That avoids hard-coding confirm behavior across services.

## 11. Trade-Offs And Known Gaps

### 1. Coupon domain is still a stub

This is acceptable because the extension point is explicit and does not contaminate the aggregate with fake coupon rules.

### 2. Shipping is intentionally simple

Flat-rate shipping is enough to keep the checkout architecture clean while the delivery pricing domain is still evolving.

### 3. Order schema still carries legacy assumptions

The order model is more fulfillment-oriented than snapshot-oriented.

That is why checkout stores the stronger commercial snapshot and order is produced from it.

### 4. Confirm does reserve then commit in one transaction

That is correct now because there is no payment gap.

When payment is introduced, the order of operations should change to preserve reserved stock through the payment wait state.

### 5. Multi-cart checkout is intentionally out of scope

This implementation is the correct building block for multi-seller orchestration later, but it does not attempt to solve that problem inside the aggregate.

## 12. Production Guidance

Recommended next steps before broad rollout:

- add idempotency protection for `/api/checkouts/confirm`
- integrate a real coupon domain behind `CheckoutCouponService`
- replace flat shipping with seller policy / distance-aware quoting
- introduce payment-aware lifecycle using `PENDING_PAYMENT`
- add expiration cleanup for future unpaid checkouts

Current design is intentionally conservative:

- clean aggregate boundaries
- PostgreSQL-friendly consistency
- no preview reservation
- no draft checkout persistence
- future payment path prepared without forcing the complexity today
