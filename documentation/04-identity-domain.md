# Identity Domain

## Responsibilities

The identity domain owns authentication accounts, role authorities, JWT issuance, refresh-token sessions, guest upgrades, OAuth identity linking, password changes, and root-account bootstrap.

`AppUser.id` is the sole public and local identity. It is a UUIDv7 generated in application code. The JWT claim name remains `public_uid`, but its value is now the direct string form of `AppUser.id`.

Routes and JWT claim names are unchanged.

## Authentication

Local and OAuth users share `AppUser`. Account checks use the standard fields on that entity:

- enabled
- account locked
- account expiration
- credential expiration
- provider and provider ID

Resolving a JWT parses `public_uid` as UUID and loads that `AppUser`. No lookup or activation state exists outside the account row.

Refresh tokens remain opaque, hashed, device-aware sessions. Logout revokes refresh tokens. Logout-all does not disable the account; account disabling is an explicit account-management operation.

## UUIDv7 Generation

JUG `5.2.0` provides the shared thread-safe UUIDv7 generator. Hibernate's custom identifier generator:

- runs before insert
- preserves an explicitly assigned UUID
- otherwise generates UUIDv7

Media and server-created device identifiers use the same utility. Client-provided UUIDs are accepted without requiring version 7.

Human-facing short references and credentials use `SecureRandom`, not UUIDv7 bytes or prefixes.

## Actor Model

The supported authorities remain customer, guest, seller, delivery company, driver, admin, and root. Seller and delivery-company permissions are separate.

Customer, seller, admin, and delivery-company profile tables share their primary key with `app_users` through `@MapsId`. A guest also has a customer profile and can be upgraded without changing identity.

Identity-backed foreign keys are UUID throughout the application and schema. Resource IDs unrelated to identity remain numeric.

## Bootstrap

The root account is created by `RootAccountBootstrap` when these settings are supplied:

- `app.bootstrap.root.email`
- `app.bootstrap.root.password-hash`
- `app.bootstrap.root.name`

Environment aliases are `ADMIN_EMAIL`, `ADMIN_PASS_HASH`, and `ADMIN_NAME`. The bootstrap adds `ROLE_ADMIN` and `ROLE_ROOT`, creates the shared-ID admin profile, and relies on the AppUser UUIDv7 generator for a new account.

## API Compatibility

- Existing routes are preserved.
- Existing JWT claim names are preserved.
- `public_uid`, customer IDs, seller IDs, user IDs, and delivery-company IDs serialize as UUID strings.
- storefront `sellerId` fields serialize as UUID strings.
- product, variant, collection, store, cart, order, shipment, address, and driver IDs remain JSON numbers.
