# App User Domain Reference

## Overview

The `App User` domain defines the platform account model and the application-level user specializations built on top of it.

It is responsible for:

- authentication-facing user persistence
- account status and role management
- public identity mapping
- customer registration
- seller upgrade from an existing customer
- user-owned address associations

This domain is implemented primarily in:

- `com.bun.platform.identity`
- `com.bun.platform.appUser`

## Package Summary

### `com.bun.platform.identity`

Provides the base account model and authentication support.

Key responsibilities:

- define the root `AppUser` entity
- integrate with Spring Security through `UserDetails`
- manage public UUID exposure through `UserIdentityMap`
- register users and issue account-level updates through `AppUserService`

### `com.bun.platform.appUser`

Provides application-specific user roles and address ownership.

Key responsibilities:

- model `Customer` and `Seller`
- manage user-address relationships through `AppUserAddress`
- expose customer registration and seller onboarding APIs

## Type Reference

### `AppUser`

**Kind:** entity  
**Package:** `com.bun.platform.identity`  
**Implements:** `UserDetails`

#### Description

Represents the root account record used by authentication, authorization, and profile-level operations.

#### Responsibilities

- store unique login identifier and encoded password
- expose granted authorities derived from assigned roles
- maintain account lifecycle state used by Spring Security
- persist avatar reference and audit timestamps

#### Key Fields

- `id`: internal primary key
- `username`: unique login name, stored as email in current flows
- `name`: display name
- `password`: encoded password
- `phone`: optional phone number
- `avatarImageId`: media UUID
- `roles`: persisted role set
- `userType`: derived textual role summary
- `enabled`: authentication enable flag
- `accountLocked`: lock flag
- `accountExpiresAt`: optional account expiry timestamp
- `credentialsExpireAt`: optional credentials expiry timestamp
- `failedLoginAttempts`: authentication failure counter
- `lockedAt`: lock timestamp
- `lastLoginAt`: last successful login timestamp

#### Persistence Notes

- mapped to `app_users`
- soft delete enabled through Hibernate
- roles persisted in `user_roles`

#### Public Behavioral Contract

- `isAccountNonExpired()` returns `false` only when `accountExpiresAt` is in the past
- `isAccountNonLocked()` returns `false` when the account is locked
- `isCredentialsNonExpired()` returns `false` only when `credentialsExpireAt` is in the past
- `isEnabled()` mirrors the persisted `enabled` flag
- `addRole(Role)` also refreshes `userType`

### `Customer`

**Kind:** entity  
**Package:** `com.bun.platform.appUser`

#### Description

Represents the customer specialization of an `AppUser`.

#### Responsibilities

- identify accounts that completed customer onboarding
- provide a specialization root for customer-only workflows

#### Persistence Notes

- mapped to `customers`
- uses shared primary key composition through `@MapsId`
- `Customer.id == AppUser.id`

### `Seller`

**Kind:** entity  
**Package:** `com.bun.platform.appUser`

#### Description

Represents the seller specialization of an existing account.

#### Responsibilities

- mark an account as seller-enabled
- retain the selected seller address reference
- add `ROLE_SELLER` to the underlying `AppUser`

#### Key Fields

- `id`
- `appUser`
- `appUserAddressId`

#### Persistence Notes

- mapped to `sellers`
- uses shared primary key composition through `@MapsId`

### `AppUserAddress`

**Kind:** entity  
**Package:** `com.bun.platform.appUser`

#### Description

Represents a user-specific address association that links one user to one reusable address record and stores per-user delivery metadata.

#### Responsibilities

- connect `AppUser` to `Address`
- store point-based geo location
- store phone and delivery details specific to that user-address pair
- mark one address as primary for the user

#### Key Fields

- `id`
- `appUser`
- `address`
- `location`
- `buildingNumber`
- `apartmentNumber`
- `floor`
- `additionalInfo`
- `isPrimary`
- `addressPhone`
- `createdAt`
- `updatedAt`

#### Persistence Notes

- mapped to `app_user_address`
- soft delete enabled
- unique constraint on `(user_id, address_id)`
- geometry stored as `Point` with SRID `4326`

#### Public Behavioral Contract

- `getLatitude()` and `getLongitude()` expose coordinate values when location exists
- `setLocation(latitude, longitude)` creates a geometry point
- `hasLocation()` returns `true` only when point data exists

### `UserIdentityMap`

**Kind:** entity  
**Package:** `com.bun.platform.identity`

#### Description

Maps an internal numeric user ID to an externally safe UUID.

#### Responsibilities

- prevent exposure of sequential internal IDs
- provide a stable public identifier for JWT and API usage
- track active/inactive identity state

#### Key Fields

- `userId`
- `user`
- `publicId`
- `active`
- `createdAt`
- `updatedAt`

#### Persistence Notes

- mapped to `user_identity_map`
- one-to-one with `AppUser`
- unique constraint on `public_id`

## Service Reference

### `AppUserService`

**Kind:** application service  
**Package:** `com.bun.platform.identity.service`

#### Description

Provides core account persistence, profile maintenance, password management, and avatar updates.

#### Main Operations

- `loadUserByUsername(String)`
- `saveAppUser(AppUserRegisterReq, Set<Role>)`
- `findAppUserInfoById(Long)`
- `getAppUser(Long)`
- `updateAppUserHelper(Long, UpdateAppUserDto)`
- `getUpdatedAppUserInfo(Long, UpdateAppUserDto)`
- `changePassword(UUID, Long, ChangePasswordReq)`
- `UploadAndSetAvatar(MultipartFile, Long)`

#### Behavioral Guarantees

- usernames are rejected if already present
- passwords are encoded before persistence
- a `UserIdentityMap` is created immediately after base-user persistence
- password changes invalidate all active devices through `LogoutService`

### `CustomerService`

**Kind:** application service  
**Package:** `com.bun.platform.appUser.services`

#### Description

Owns customer onboarding.

#### Main Operations

- `createCustomer(AppUserRegisterReq)`
- `findCustomerById(Long)`

#### Behavioral Guarantees

- creates an `AppUser` with `ROLE_CUSTOMER`
- persists the `Customer` specialization using shared ID mapping
- creates wallet state through `WalletService`
- returns access and refresh credentials after successful registration

### `SellerService`

**Kind:** application service  
**Package:** `com.bun.platform.appUser.services`

#### Description

Upgrades an existing customer account into a seller account.

#### Main Operations

- `createSeller(Long, String, CreateSellerDto)`
- `findSellerById(Long)`

#### Preconditions

- source account must already exist as a `Customer`
- seller must not already exist for the same `AppUser`
- `storeDto` must be present
- either `addressDto` or `appUserAddressId` must be supplied

#### Behavioral Guarantees

- adds `ROLE_SELLER` to the linked `AppUser`
- persists `Seller`
- creates or attaches the seller address
- creates store and merchant balance side effects
- reissues tokens so updated roles are visible immediately

### `AppUserAddressService`

**Kind:** application service  
**Package:** `com.bun.platform.appUser.services`

#### Description

Owns the user-address association lifecycle.

#### Main Operations

- `getUserAddresses(Long)`
- `getPrimaryAddress(Long)`
- `addOrUpdateAddressToUser(Long, AddUserAddressReq)`
- `removeAppUserAddress(Long)`
- `setPrimaryAddress(Long, Long)`
- `userHasAddress(Long, Long)`
- `countUserAddresses(Long)`

#### Behavioral Guarantees

- reuses an existing association for the same `(AppUser, Address)` pair
- requires either coordinates or additional address info
- requires `addressPhone` on creation unless already stored
- clears the previous primary flag before assigning a new primary address

## REST API Reference

### Customer Registration

**Controller:** `CustomerController`  
**Base path:** `/api/customer`

#### Endpoint

- `POST /register`

#### Request Type

- `AppUserRegisterReq`

#### Response

- token payload generated through `AuthLoginService`

### Seller Registration

**Controller:** `SellerController`  
**Base path:** `/api/seller`

#### Endpoint

- `POST /register`

#### Request Type

- `CreateSellerDto`

#### Response

- token payload containing updated seller role information

### User Address Management

**Controller:** `UserAddressController`  
**Base path:** `/api/user/addresses`

#### Endpoints

- `GET /`
- `GET /primary`
- `POST /{addressId}`
- `DELETE /{addressId}`
- `PUT /{addressId}/primary`
- `GET /{addressId}/exists`
- `GET /count`

#### Authentication Model

- current user is resolved from JWT claims

## DTO Reference

### `AppUserRegisterReq`

#### Purpose

Registration request for new customer accounts.

#### Fields

- `username`
- `password`
- `name`
- `phone`
- `deviceId`

#### Validation Summary

- username must be a valid email
- password must satisfy length and character-composition rules
- `deviceId` must be a UUID string

### `CreateSellerDto`

#### Purpose

Request model for seller upgrade.

#### Fields

- `addressDto`
- `appUserAddressId`
- `storeDto`

### `AddUserAddressReq`

#### Purpose

Request model for creating or updating a user-address association.

#### Fields

- `addressId`
- `isPrimary`
- `latitude`
- `longitude`
- `buildingNumber`
- `apartmentNumber`
- `floor`
- `additionalInfo`
- `addressPhone`

## Persistence Reference

### Primary Tables

- `app_users`
- `user_roles`
- `customers`
- `sellers`
- `admins`
- `drivers`
- `app_user_address`
- `user_identity_map`

### Structural Constraints

- unique username on `app_users`
- shared primary keys for specialization tables through `@MapsId`
- unique `(user_id, address_id)` on `app_user_address`
- unique `public_id` on `user_identity_map`

## Domain Invariants

- username must be unique
- password is persisted encoded, never raw
- seller registration is an upgrade path, not an independent root registration flow
- one user-address relation exists at most once per `(user, address)`
- only one primary address should remain for a user after service operations
- public UUID is the external-safe identifier for user exposure

## Side Effects

- customer registration creates a wallet
- seller registration creates merchant balance state
- seller registration creates or updates store state
- successful login updates `lastLoginAt` and resets failed login attempts
- password change invalidates all active sessions

## Exception Handling

### English

- Error responses for this domain should use the platform's bilingual error envelope with `timestamp`, `path`, English details, and Arabic details.
- `400 Bad Request`: use for invalid profile data, invalid username format, same old/new password, missing `storeDto` or `addressDto` during seller upgrade, invalid address phone, or invalid latitude/longitude input.
- `404 Not Found`: use when the target `AppUser`, `Customer`, seller-related record, or referenced address association does not exist.
- `409 Conflict`: use when the request violates current state, such as upgrading an already registered seller or creating a duplicate user-address or identity relation.
- `401 Unauthorized` and `403 Forbidden`: use for invalid credentials, expired tokens, locked or disabled accounts, or role-based access denial.
- `500 Internal Server Error`: reserve for unexpected wallet/store bootstrap failures, media upload failures, or any unclassified runtime or infrastructure error.
- Current implementation note: this domain already benefits from the global bilingual exception layer, but many failures still depend on generic exceptions instead of dedicated app-user error codes.

### العربية

- يجب أن تستخدم أخطاء هذا النطاق غلاف الأخطاء الموحد ثنائي اللغة في المنصة بحيث يتضمن `timestamp` و`path` ورسائل واضحة بالعربية والإنجليزية.
- `400 طلب غير صحيح`: يستخدم عند وجود بيانات ملف شخصي غير صالحة، أو اسم مستخدم غير صالح، أو كلمة مرور جديدة مطابقة للقديمة، أو غياب `storeDto` أو `addressDto` أثناء ترقية البائع، أو رقم هاتف عنوان غير صالح، أو إحداثيات غير صحيحة.
- `404 غير موجود`: يستخدم عندما لا يكون `AppUser` أو `Customer` أو سجل البائع المطلوب أو علاقة العنوان المرجعية موجودة.
- `409 تعارض`: يستخدم عندما يتعارض الطلب مع الحالة الحالية، مثل محاولة ترقية مستخدم مسجل بالفعل كبائع أو إنشاء علاقة عنوان أو هوية مكررة.
- `401 غير مصادق` و`403 ممنوع`: يستخدمان عند فشل بيانات الدخول، أو انتهاء صلاحية الرمز، أو كون الحساب مقفولاً أو معطلاً، أو عدم امتلاك الصلاحية المناسبة.
- `500 خطأ داخلي في الخادم`: يحجز للأعطال غير المتوقعة مثل فشل إنشاء المحفظة أو المتجر، أو فشل رفع الوسائط، أو أي خطأ تشغيلي أو بنيوي غير مصنف.
- ملاحظة تنفيذية حالية: هذا النطاق يستفيد بالفعل من طبقة الأخطاء الثنائية اللغة، لكن كثيراً من الحالات ما زالت تعتمد على استثناءات عامة بدلاً من رموز أخطاء متخصصة خاصة بنطاق المستخدم.

## Security Notes

- `AppUser` is used directly by Spring Security
- JWT-based endpoints resolve local user identity either from `uid` or `UserIdentityService`
- account enable, lock, account-expiry, and credentials-expiry flags participate in authentication decisions

## Implementation Notes

- the schema evolved from inheritance to composition; current behavior is composition-based
- `identity` and `appUser` should be documented together because they form one runtime domain
- `UserAddressController` currently returns entity-shaped responses rather than a dedicated response DTO layer
- some request fields in `AddUserAddressReq` are defined but not fully copied into the entity by the current service implementation
