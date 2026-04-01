# Validation Engine Documentation

## What ValidationContext is

`ValidationContext` is a transient reconciliation object. It is not a replacement for the cart aggregate.

It contains:

- batched product projections
- batched inventory quantities
- validation mode
- collected decisions:
  - price updates
  - quantity adjustments
  - status updates
  - snapshot refreshes
  - removals
- collected item update records and messages

## Version-based validator skip

In preview mode, each `CartItem` stores the `variantPurchaseVersion` and `variantAttributesVersion` it was last validated against. On the next read, `CartValidator` compares these stored values against the current variant:

- If `purchaseVersion` matches → validators that `dependsOnPurchaseVersion()` are skipped (covers `VariantValidator`, `QuantityValidator`, `PriceSnapshotValidator`)
- If `attributesVersion` matches → validators that `dependsOnAttributeVersion()` are skipped (covers `SelectionValidator`)
- `StockValidator` declares dependency on neither version and always runs
- In reconcile mode all freshness flags are overridden to false — all validators always run
- If the variant no longer exists the freshness flags are false — `VariantValidator` runs and removes the item

This eliminates redundant DB round-trips on unchanged items during high-frequency reads.

## Validator responsibilities

Validators only read:

- the current cart item
- the validation context

Validators only write:

- decisions into the validation context

Validators do not:

- mutate entities directly
- fetch data per item
- build response models

## Lifecycle

### 1. Validate

- `CartValidator` builds a single batched context
- a baseline `AVAILABLE` status is recorded
- current variant snapshots are recorded for refresh
- validators run in deterministic order

### 2. Collect decisions

Validators emit:

- messages
- status changes
- quantity clamps
- price refreshes
- removals

### 3. Apply

`ValidationContext.applyUpdates(...)` mutates cart items only after all rules have run.

### 4. Remove

`CartValidationService` removes lines marked for removal from the cart aggregate.

### 5. Build response

- `CartView.items` comes from the current cart state after reconciliation
- `CartValidationOverview.itemUpdates` comes from the context
- top-level messages are flattened from item updates
