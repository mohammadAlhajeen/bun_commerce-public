# App User Domain

## Identity Model

`AppUser` is the platform's only user identity record. Its `id` is a PostgreSQL `UUID` generated as UUIDv7 by the application through JUG's `Generators.timeBasedEpochGenerator()`.

There is no identity mapping table or secondary public identifier. The same UUID is:

- `AppUser.id`
- the JWT `public_uid` claim
- the customer, seller, admin, or delivery-company profile ID
- the actor ownership value stored by addresses, media, wallets, carts, checkout, orders, shipments, catalog records, offers, subscriptions, stores, and cache events

Explicitly assigned UUIDs remain supported for fixtures and bootstrap data. Application-created users receive UUIDv7 on insert.

## Roles And Profiles

Roles remain Spring Security authorities and preserve the existing route contracts:

- `ROLE_GUEST`
- `ROLE_CUSTOMER`
- `ROLE_SELLER`
- `ROLE_DELIVERY_COMPANY`
- `ROLE_DRIVER`
- `ROLE_ADMIN`
- `ROLE_ROOT`

`Customer`, `Seller`, `Admin`, and `DeliveryCompany` use `@MapsId`, so each profile row has exactly the same UUID as its `AppUser` row. Sellers and delivery companies remain separate roles and profiles.

A guest is a customer identity with restricted permissions. Guest checkout creates an `AppUser` with `ROLE_GUEST` and a customer profile. Registration or OAuth can upgrade that same record in place to `ROLE_CUSTOMER`; the UUID and customer-owned data do not change.

Drivers are different: `Driver.id` is a numeric resource ID, while `Driver.userId` optionally links to the driver's UUID `AppUser` identity.

## Identifier Rules

UUIDv7 is used for generated identity and UUID resource identifiers, including:

- `AppUser.id`
- generated media IDs
- server-generated device IDs

Client-supplied device UUIDs may use any UUID version.

Secrets and short human-facing references do not use UUID timestamps. Guest usernames and passwords, plus 12-character order, checkout, and shipment references, use `SecureRandom`.

Independent business resources keep numeric IDs. This includes products, variants, collections, stores, carts, orders, shipments, addresses, and drivers.

## Ownership

All identity-backed ownership fields use `UUID` in Java and PostgreSQL. Important examples are `customerId`, `sellerId`, `appUserId`, `deliveryCompanyId`, and `companyId`.

Storefront ownership uses UUID for:

- `stores.seller_id`
- `product_definitions.seller_id`
- `product_collections.seller_id`

Public store routes continue to use slugs. Product filtering, sorting, pagination, media, collections, categories, price bounds, active offers, and cache invalidation retain their existing behavior.

## Persistence Invariants

- `app_users.id` is `UUID` and has no database sequence.
- actor profile primary keys are also foreign keys to `app_users.id`.
- actor foreign keys must never be declared as `BIGINT`.
- the application generates UUIDv7; PostgreSQL does not provide a custom `uuid_v7()` function.
- root/admin bootstrap is application-managed and receives UUIDv7 like other generated accounts.
