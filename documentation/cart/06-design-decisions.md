# Cart Design Decisions

## Why self-healing over exceptions

Cart reconciliation is driven by external state that changes independently:

- price updates
- stock changes
- variant deactivation
- option model changes

For these cases, rejecting the entire cart read creates a worse user experience than repairing the cart and explaining what changed.

## Why Cart is the source of truth

The user-facing cart must come from persisted aggregate state after repairs are applied.  
If the response is built from a transient context, the frontend can receive:

- missing unchanged items
- removed items that still appear
- stale quantities
- stale prices

That is exactly what this refactor removes.

## Why ValidationContext is not the source of truth

The context exists to collect and order decisions.  
It is intentionally limited to:

- rule input
- rule output
- reconciliation metadata

It cannot own cart state because it has no lifecycle outside a validation run.

## Why validators are pure

Pure validators are easier to:

- reason about
- order deterministically
- unit test
- extend later for coupons and shipping

They also keep orchestration responsibility inside the service layer.

## Trade-offs

- Batched full projections are heavier than minimal per-validator lookups, but they remove N+1 behavior and keep rules pure.
- Price increases are not auto-acknowledged, which preserves correctness but requires a separate acknowledgment flow.
- The cart still depends on external product projections, so complete isolation is not practical in a commerce system.
