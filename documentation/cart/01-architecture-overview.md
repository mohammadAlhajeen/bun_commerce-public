# Cart Architecture Overview

## Purpose

The Cart domain owns seller-scoped shopping carts and reconciles them against current catalog and inventory data without scattering business rules across application services.

## Core design

- `Cart` is the source of truth for active cart state.
- `ValidationContext` is a transient decision collector used during reconciliation.
- Validators are pure rule evaluators.
- `CartValidationService` orchestrates:
  - load cart
  - validate
  - apply decisions
  - remove invalid items
  - build response

## Validation modes

- Preview mode:
  - customer reads or updates cart
  - auto-fixable issues are applied
  - price increases are warnings
- Reconcile mode:
  - same reconciliation pipeline
  - price increases become blocking
  - response still returns the repaired cart unless it becomes empty

## Runtime data flow

1. Lock and load the cart aggregate.
2. Build a batched validation context from:
   - full variant projections
   - inventory quantities
3. Run validators in deterministic order.
4. Apply collected decisions to the cart aggregate.
5. Remove items marked as invalid.
6. Persist only if the cart actually changed.
7. Build `CartView` from the post-mutation cart.
8. Attach item updates and messages from the context.

## Determinism guarantees

- Validator order is explicit and sorted by `CartItemValidator.order()`.
- Competing quantity decisions merge by minimum value, not by last writer.
- Response items are always built from the cart, never from the validation context.

## Identity extraction

Customer identity for all customer-facing operations is resolved from the JWT by `UserIdentityService.extractUserIdFromJwt()`. The `customerId` is never accepted as a request payload field — it is always injected by the controller from the authenticated token.

## Domain events

CartService and CartValidationService publish domain events via `ApplicationEventPublisher`. All listeners use `@TransactionalEventListener(phase = AFTER_COMMIT)` to guarantee events fire only after the state change is durable.

Published events:

- `CartCreatedEvent` — new open cart created
- `CartItemAddedEvent` — variant added or quantity merged
- `CartItemRemovedEvent` — item explicitly deleted by customer
- `CartItemQuantityUpdatedEvent` — quantity mutated
- `CartCheckedOutEvent` — cart submitted to reconcile validation
- `CartItemsAutoRemovedEvent` — one or more items removed during reconciliation
- `CartClosedEvent` — cart closed because all items were auto-removed

`CartEventListener` handles all seven events and logs them at INFO or WARN level.

## Live variant summary

`CartProductService.getVariantSummaries()` issues a single batch JPQL query via `VariantSummaryRow` — a JPA projection interface on the variant domain — to return current prices and media for a list of variant IDs. This is used by `CartService.getCartSummary()` to serve live data without relying on cart snapshots.

## Cart view cache

`CartValidationService.getCartView()` (the non-reconcile read path) is annotated with `@Cacheable("cart_view")`, keyed by `cartId`, and backed by a Caffeine in-memory cache with a **30-second TTL** and a maximum of 5 000 entries.

The cache is evicted on every state-changing operation:

- `validateCart` — called after addToCart, updateQuantity, adjustQuantities, acknowledgePrices
- `validateCartForReconcile` — called on the reconcile endpoint
- `removeItem` — evicts directly via `CacheManager` (does not go through `CartValidationService`)

The 30-second TTL is a safety net. Explicit eviction ensures reads after writes always return fresh state.

## Boundaries

- Product and inventory remain external domains.
- Cart stores:
  - variant id
  - selection snapshots
  - price snapshots
  - quantity snapshots
  - validation status
- Cart does not own inventory reservation or final order confirmation.
