# Cart Domain Documentation Index

The Cart domain documentation now lives in `documentation/cart/` and is organized as a production-facing package.

## Included documents

1. `documentation/cart/01-architecture-overview.md`
2. `documentation/cart/02-domain-model.md`
3. `documentation/cart/03-validation-engine.md`
4. `documentation/cart/04-validation-rules.md`
5. `documentation/cart/05-api-response-contract.md`
6. `documentation/cart/06-design-decisions.md`
7. `documentation/cart/07-future-extensions.md`
8. `documentation/cart/08-known-limitations.md`

## Current implementation summary

- `Cart` is the source of truth for active cart state.
- `ValidationContext` is a decision collector, not a state container.
- Validation runs in two explicit modes:
  - preview
  - reconcile
- The runtime pipeline is:
  - validate
  - collect decisions
  - apply updates to cart items
  - remove invalid items
  - build response from the post-mutation cart
- `CartView.items` always reflects the current cart after reconciliation.
- `CartView.removedItems` carries items auto-removed during the current validation run.
- `CartValidationOverview.itemUpdates` carries the adjustment and removal history for the current validation run.
- Customer identity is always resolved from JWT — never accepted from request body.
- Seven domain events are published after successful commits via `@TransactionalEventListener`.
- `CartItemSummaryView` provides a lightweight live summary sourced from the variant domain via `VariantSummaryRow`.
- `selection_key` is stored as a SHA-256 hex digest (64 chars) of the sorted raw selection string; empty for items with no selections.
- `CartValidationService.getCartView()` is cached in `cart_view` (Caffeine, 30-second TTL) and evicted on every state-changing operation.
- Validators skip work when version counters are fresh: `purchaseVersion` gates price/availability/quantity validators; `attributesVersion` gates `SelectionValidator`; `StockValidator` always runs.

## Customer endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/cart/my` | Get all open carts for the authenticated customer |
| `GET` | `/api/cart/my/{sellerId}` | Get cart for a specific seller with live validation |
| `GET` | `/api/cart/my/cart/{cartId}` | Get a specific cart by ID |
| `GET` | `/api/cart/my/cart/{cartId}/summary` | Get live item summary (prices + image) |
| `POST` | `/api/cart/add` | Add an item — customerId from JWT |
| `PUT` | `/api/cart/items/{itemId}/quantity` | Update item quantity |
| `DELETE` | `/api/cart/items/{itemId}` | Remove an item |
| `POST` | `/api/cart/{cartId}/validate-reconcile` | Full reconcile pass before order submission |
| `POST` | `/api/cart/{cartId}/acknowledge-prices` | Explicitly sync price-review state |
| `POST` | `/api/cart/{cartId}/adjust-quantities` | Clamp quantities to stock limit |

## Main response contract

- `CartView.items`: surviving cart items after reconciliation.
- `CartView.removedItems`: items removed during the current reconciliation run.
- `CartView.totals`: subtotal, discount, and total computed from current cart state.
- `CartView.validation.messages`: flattened validation messages for the whole run.
- `CartView.validation.itemUpdates`: per-item adjustments, price diffs, removals, and blocking states.

## Validation policy summary

- Auto-fix:
  - quantity clamps
  - inactive or unavailable item removal
  - price decreases
  - neutral price-structure refreshes
- Warning:
  - preview-time price increases
  - quantity clamps
  - removed or unavailable lines
- Blocking:
  - reconcile-time price increases
  - invalid selections that require customer action
- Exceptions:
  - cart not found
  - cart item not found
  - invalid add-to-cart command payload
  - add-to-cart variant unavailable

## Supporting diagrams

See `documentation/08-cart-uml.md` for the updated diagrams.
