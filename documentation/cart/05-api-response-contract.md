# Cart API Response Contract

## CartView

`CartView` contains:

- `cartId`
- `sellerId`
- `items`
- `removedItems`
- `totals`
- `validation`

## items

`items` always represents the current cart after reconciliation.

Each item includes:

- cart item identity
- variant and product identifiers
- product and variant display names
- current quantity
- current price snapshot (`basePrice`, `finalPrice`)
- `mainMediaUrl` — resolved to `/api/public/media/{uuid}` via `MediaUtil`
- current selection list
- item-level validation details for this response

## removedItems

`removedItems` contains the items that were auto-removed during the current validation run.

Each entry is the same shape as an `items` entry so the frontend can render a "removed lines" section without additional API calls.

Frontend guidance:

- show `removedItems` as a dismissed lines section after the cart
- items in `removedItems` must not be shown as active cart lines

## totals

`totals` is computed from current cart items:

- `subtotal`: sum of base price x quantity
- `discount`: sum of discount x quantity
- `total`: sum of final price x quantity

## validation.messages

This is the flattened list of validation messages across the whole cart.

Frontend guidance:

- `INFO`: show non-blocking refresh information
- `WARNING`: show repair or review information
- `BLOCKING`: disable checkout completion until resolved

## validation.itemUpdates

This list describes item-level changes generated during the validation run.

Frontend guidance:

- use `removed=true` to explain why a line disappeared
- use `suggestedQuantity` to explain quantity clamps
- use `priceDifference` to show price drift
- use `oldStatus` and `newStatus` to animate or badge item state changes

## CartItemSummaryView — live summary endpoint

Available at `GET /api/cart/my/cart/{cartId}/summary`.

Returns a lightweight per-item snapshot fetched **live from the variant domain** — not from the cart's stored price snapshots.

Each entry contains:

- `variantId`
- `variantName`
- `mainMediaUrl`
- `basePrice`
- `finalPrice` (current effective price including active offers)

Use this endpoint when a fast, image-and-price summary is needed (e.g., order review screens, mini-cart drawers) without triggering a full validation pass.

## Frontend interpretation rules

- trust `items` for current cart rendering
- trust `removedItems` for displaying auto-removed lines during the last reconciliation
- trust `validation.itemUpdates` for what changed during this reconciliation
- use the summary endpoint for lightweight read-only display; use the full `CartView` endpoints when interactive validation state is needed
- do not reconstruct current cart state from messages alone
- use `POST /api/cart/{cartId}/acknowledge-prices` when the client wants to explicitly sync remaining price-review state
- use `POST /api/cart/{cartId}/validate-reconcile` to trigger a full reconcile pass before order submission
