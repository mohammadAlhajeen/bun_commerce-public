# Known Limitations

## Identity and authorization

**Resolved.** Customer identity is now resolved exclusively from the JWT on all customer-facing endpoints. The `customerId` field has been removed from `AddToCartRequest`. The controller extracts the identity via `UserIdentityService.extractUserIdFromJwt()` which reads the `public_uid` UUID claim and maps it to the internal Long id.

Remaining gap: `removeItem` and `updateQuantity` do not yet verify that the target item belongs to the authenticated customer. Cross-customer item manipulation is currently prevented only by business logic paths, not by an explicit ownership assertion.

## Pricing context

`CartPriceService` still accepts `customerId` but does not use it.  
The structure is ready for user-specific pricing, but the implementation is not yet there.

## Removed item presentation

**Resolved.** `CartView` now contains a dedicated `removedItems` list. Items auto-removed during a validation run are captured before removal and surfaced in this separate field. The frontend can render a dismissed-lines section without reconstructing removals from messages.

## Checkout reservation

Cart validation does not reserve stock.  
Final checkout correctness still depends on an order or reservation step that locks or reserves inventory atomically.

## Item ownership enforcement

`updateQuantity` and `removeItem` accept a raw `itemId` without verifying that the item belongs to the authenticated customer's cart. An authenticated customer could theoretically modify another customer's cart item if they know the ID. This should be fixed by loading the cart through `customerId` before applying the mutation.

## Controller surface

`MultiCartOrderController` is still empty, so cross-seller checkout orchestration remains outside the current cart package.

## Legacy DTO surface

`CartValidation` and `UpdateCartItemRequest` still exist even though the active HTTP response flow uses `CartView` and `CartValidationOverview`.  
They are harmless but not part of the primary path.
