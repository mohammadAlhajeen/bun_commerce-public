# Bun Commerce Documentation

Public architecture documentation for **Bun Commerce**, a full-stack marketplace commerce platform built as a portfolio and product engineering project.

This repository is intentionally documentation-focused. It does not contain the private application source code, production data, secrets, or a runnable deployment package. The goal is to show the engineering decisions, domain modeling, API boundaries, and system design behind the project.

## Project Summary

Bun Commerce models a marketplace-style commerce system with customer, seller, delivery, and admin workflows. The private implementation uses a Java/Spring backend and a Next.js storefront.

The platform covers:

- product catalog, variants, attributes, media, collections, offers, and search;
- customer cart validation, price-change acknowledgement, checkout preview, and checkout confirmation snapshots;
- order lifecycle, seller order handling, WhatsApp-oriented order requests, and public order lookup;
- seller store pages, store profile editing, filtering, pagination, standardized product cards, and storefront caching;
- delivery companies, drivers, shipment assignment, delivery status transitions, and tracking;
- identity, JWT authentication, refresh sessions, role-based access, global product/store search, and rate limiting;
- subscriptions, payment/wallet abstractions, geographic/address modeling, and media storage.

No production users, revenue, or traction are claimed. This project is presented as evidence of software engineering work: domain design, architecture, persistence modeling, security thinking, API design, testing strategy, and deployment planning.

## Why This Repo Exists

For hiring reviewers, this public repository answers:

- What kind of system did I build?
- How did I divide the system into domains?
- What business rules and invariants did I model?
- How do cart, checkout, order, delivery, catalog, and identity interact?
- What trade-offs did I document?
- Where are the known gaps and future improvements?

The private source repository contains implementation details. This public repository exposes the architectural reasoning.

## Architecture Overview

Bun Commerce is designed as a modular monolith with microservice-ready boundaries. Each major domain owns its own model, service layer, persistence concerns, DTO/API contract, and documented invariants.

Main domains:

| Domain | Responsibility |
| --- | --- |
| App User | Customer/seller/admin profile concerns and account-facing user workflows |
| Identity | Authentication, JWT access tokens, refresh-token sessions, public identity mapping, account security |
| Catalog | Categories, attributes, products, variants, inventory, product cards, collections, offers, search |
| Cart | Store-scoped carts, item snapshots, validation engine, reconciliation, price and stock repair |
| Checkout | Stateless preview and immutable checkout confirmation snapshots before order creation |
| Order | Committed commercial transactions, seller/customer/admin order views, lifecycle transitions |
| Seller Store | Public seller storefront read model, slug routing, filtering, pagination, cache invalidation |
| Delivery | Delivery companies, drivers, shipment assignment, shipment state transitions |
| Address | Country/state/city/street hierarchy, user addresses, delivery address snapshots |
| Subscription | Plans, subscription lifecycle, usage limits, payment simulation hooks |
| Homepage | Public homepage payload assembly and product-card optimization |

## Documentation Map

Start here:

- [Current Architecture Refactor](documentation/14-current-architecture-refactor.md)
- [Product Domain](documentation/02-product-domain.md)
- [Cart Architecture](documentation/cart/01-architecture-overview.md)
- [Cart Validation Engine](documentation/cart/03-validation-engine.md)
- [Checkout Domain](documentation/10-checkout-domain.md)
- [Order Domain](documentation/11-order-domain.md)
- [Seller Store Domain](documentation/12-seller-store-domain.md)
- [Identity Domain](documentation/04-identity-domain.md)
- [Delivery Domain](documentation/09-delivery-domain.md)
- [Subscription Domain](documentation/07-subscription-domain.md)
- [Homepage Backend](documentation/13-homepage-backend.md)
- [Standardized Product Card Refactor](documentation/standardized-product-card-refactor.md)
- [JMeter Load Testing](documentation/jmeter-load-testing.md)

UML-oriented notes are also available next to the domain documents, for example:

- [Product UML](documentation/02-product-uml.md)
- [Cart UML](documentation/08-cart-uml.md)
- [Checkout UML](documentation/10-checkout-uml.md)
- [Order UML](documentation/11-order-uml.md)
- [Seller Store UML](documentation/12-seller-store-uml.md)

## Technical Stack

Private implementation stack:

- Java 25
- Spring Boot
- Spring Web MVC, Spring Security, Spring Data JPA, Spring Validation, Spring Actuator
- PostgreSQL/PostGIS
- Flyway migrations
- Hibernate/JPA
- Caffeine caching
- JWT authentication
- Springdoc OpenAPI
- Next.js, React, TypeScript, Tailwind CSS, Radix UI
- Docker Compose and Nginx deployment planning

## Engineering Highlights

- Modular domain documentation across catalog, cart, checkout, order, delivery, identity, seller-store, subscription, address, and homepage modules.
- Current-branch read-model documentation for standardized `ProductCard`, store pages, FTS-backed product/store search, and global search.
- Cart validation model with deterministic validators, reconciliation modes, item repair, item removal, stock checks, and price-change acknowledgement.
- Checkout design that separates mutable cart state from immutable commercial confirmation snapshots.
- Product model with variants, tracked inventory, default variant rules, active/inactive lifecycle, collection membership, and cache-aware reads.
- Seller-store read model with slug-based public pages, product-card projection, filtering, pagination, and cache invalidation.
- Identity model with JWT access, refresh-token rotation, public identity mapping, account state checks, and documented security risks.
- Delivery model with driver/company workflows, shipment assignment, and delivery state transitions.
- JMeter load testing of a realistic, weighted traffic mix (homepage, product detail, search, store pages, cart sessions) across 299,400 logged requests with zero errors, documented with full per-run results and an explicit accounting of which changes between runs can and cannot be attributed to the observed latency drop.
- Written trade-off sections that identify what is implemented, what is intentionally deferred, and what should be improved before production use.

## Ownership

Copyright (c) 2026 Mohammed Alhajeen.

Bun Commerce is a private software project. This public repository is provided as architecture and portfolio documentation only. Do not treat it as an open-source implementation.
