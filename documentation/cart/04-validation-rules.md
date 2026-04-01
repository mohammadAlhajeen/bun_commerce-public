# Validation Rules

## VariantValidator

- Checks:
  - variant exists
  - variant is active
- Severity:
  - preview: WARNING
  - reconcile: WARNING
- Behavior:
  - missing variant -> remove item
  - inactive variant -> remove item

## SelectionValidator

- Checks:
  - attribute still exists and is active
  - selected value still exists and is active
  - required options are still satisfied
  - required free input is still present
- Severity:
  - preview: BLOCKING
  - reconcile: BLOCKING
- Behavior:
  - item stays in cart
  - status becomes `REQUIRES_SELECTION_UPDATE`
  - customer must resolve selections

## StockValidator

- Checks:
  - tracked stock availability
- Severity:
  - preview: WARNING
  - reconcile: WARNING
- Behavior:
  - stock `<= 0` -> remove item
  - requested quantity above stock -> clamp quantity

## QuantityValidator

- Checks:
  - current quantity against `maxQuantityPerOrder`
- Severity:
  - preview: WARNING
  - reconcile: WARNING
- Behavior:
  - clamp quantity to the current maximum

## PriceSnapshotValidator

- Checks:
  - current price snapshot against stored cart snapshot
- Severity:
  - price decrease: INFO
  - neutral price structure change: INFO
  - price increase in preview: WARNING
  - price increase in reconcile: BLOCKING
- Behavior:
  - price decrease -> refresh snapshot automatically
  - neutral price change -> refresh snapshot automatically
  - price increase -> keep snapshot unchanged until explicit acknowledgment

## Rule ordering

1. Variant
2. Selection
3. Stock
4. Quantity
5. Price

This ordering is explicit in code and not dependent on Spring injection order.
