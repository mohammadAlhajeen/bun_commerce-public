# Future Extensions

## Coupons

Recommended approach:

- add a coupon input section to `ValidationContext`
- introduce a cart-level validator after item-level price validation
- emit cart-level adjustments and messages

## Promotions

Recommended approach:

- extend product pricing projections with promotion context
- keep automatic snapshot refresh for non-increasing outcomes
- require explicit acknowledgment for customer-negative changes

## Shipping

Recommended approach:

- treat shipping as cart-level validation, not item-level
- include destination, seller shipping policy, and fulfillment method in context
- compute shipping adjustments after item removals and quantity clamps

## User-specific pricing

Recommended approach:

- make `CartPriceService` genuinely customer-aware
- enrich validation context with customer or segment pricing inputs
- keep cart snapshots per customer-specific pricing result

## Per-user limits

Recommended approach:

- add a validator after quantity and stock
- feed account-level purchase counters into context
- emit warning or blocking results depending on policy
