# Cart Domain Model

## Cart aggregate

### Responsibilities

- enforce one active seller-scoped cart per customer and seller
- own cart item lifecycle
- act as the only source of truth for current cart state
- expose aggregate operations such as:
  - add item
  - find item
  - remove item

### Invariants

- open cart uniqueness is enforced at the database level
- cart items cannot exist without a cart
- cart state returned to clients is always the post-reconciliation aggregate state

## CartItem

### Responsibilities

- represent one variant line in the cart
- hold customer quantity
- hold current validation status
- store lightweight commercial snapshots:
  - base price
  - discount
  - final price
  - max quantity
  - purchase version
  - attribute version
- persist normalized selections and a stable selection key

### Selection key

The `selectionKey` field stores a stable fingerprint of all item selections, used to detect duplicate cart entries with identical variant and selections.

- The raw string is built by sorting selections by `attributeId`, then `valueId`, formatted as `attributeId:valueId:valueText` joined with `|`.
- The raw string is then hashed with **SHA-256** and stored as a 64-character lowercase hex digest.
- An item with no selections stores an empty string.
- The hash is computed by `CartItem.generateSelectionKey()` and assigned via `CartItem.computeAndAssignSelection()` during item creation.

### What CartItem does not own

- inventory truth
- catalog truth
- pricing policy truth
- coupon logic
- shipping logic

## Boundaries with Product

Cart depends on Product for read projections only:

- variant activity
- max quantity
- option definitions
- selection definitions
- price snapshot source

Cart intentionally does not copy full product state into the aggregate.

## Boundaries with Inventory

Cart reads inventory as validation input only:

- tracked stock can clamp quantity
- zero stock can remove an item

Inventory reservation is not part of cart reconciliation and must happen in ordering or checkout reservation flow.
