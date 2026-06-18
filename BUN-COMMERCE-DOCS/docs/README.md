# Bun Commerce Public Documentation

This folder is the public documentation entry point for Bun Commerce.

Bun Commerce is a marketplace commerce platform designed around modular domain boundaries, realistic commerce workflows, and documented trade-offs. The application source code is private; this repository shares architectural notes and domain references for portfolio review.

## Main Documentation

Recommended reading order:

1. [Product Domain](../../documentation/02-product-domain.md)
2. [Cart Architecture](../../documentation/cart/01-architecture-overview.md)
3. [Cart Validation Engine](../../documentation/cart/03-validation-engine.md)
4. [Checkout Domain](../../documentation/10-checkout-domain.md)
5. [Order Domain](../../documentation/11-order-domain.md)
6. [Seller Store Domain](../../documentation/12-seller-store-domain.md)
7. [Identity Domain](../../documentation/04-identity-domain.md)
8. [Delivery Domain](../../documentation/09-delivery-domain.md)
9. [Subscription Domain](../../documentation/07-subscription-domain.md)
10. [Homepage Backend](../../documentation/13-homepage-backend.md)

## What The Docs Cover

- domain responsibilities and boundaries;
- entities, value objects, DTOs, and service responsibilities;
- REST API surfaces and ownership rules;
- persistence notes and schema-level invariants;
- cache strategy and event-driven invalidation;
- security and identity flows;
- known gaps, trade-offs, and recommended next steps.

## Public Repository Scope

Included:

- architecture notes;
- domain references;
- UML-oriented Markdown diagrams;
- portfolio README content.

Not included:

- private application source code;
- production data;
- secrets or credentials;
- runnable deployment artifacts;
- real users, revenue, or production metrics.

## Ownership

Copyright (c) 2026 Mohammed Alhajeen.

This documentation is published for review and portfolio purposes. Bun Commerce itself is not open-source software.
