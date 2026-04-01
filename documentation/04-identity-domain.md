# Identity Domain Reference

## Overview

The `identity` domain owns authentication-facing accounts, public identity mapping, JWT issuance, refresh-token session management, and profile/password operations for authenticated users.

It is implemented primarily in:

- `com.bun.platform.identity`
- `com.bun.platform.identity.controller`
- `com.bun.platform.identity.service`
- `com.bun.platform.identity.repository`
- `com.bun.platform.config.SecurityConfig`

## Responsibilities

- persist root platform accounts in `AppUser`
- expose role-based authorities to Spring Security
- map internal numeric IDs to external `public_uid` UUID values
- issue short-lived JWT access tokens
- issue and rotate hashed refresh tokens per device
- revoke sessions by device or across all devices
- enforce account activity, lock, expiry, and credential-expiry checks during refresh
- expose authenticated profile and password-change APIs

## Package Summary

### `com.bun.platform.identity`

Contains the core account and token model:

- `AppUser`
- `UserIdentityMap`
- `RefreshToken`
- `Role`

### `com.bun.platform.identity.service`

Contains the domain application services:

- `AppUserService`
- `AuthLoginService`
- `UserIdentityService`
- `RefreshTokenService`
- `LogoutService`
- `AccessTokenIssuer`
- `JwtService`
- `RefreshTokenCleanupJob`

### `com.bun.platform.identity.controller`

Exposes the identity HTTP surface:

- `AuthController`
- `AppUserController`

## Core Model

### `AppUser`

**Kind:** entity  
**Table:** `app_users`  
**Implements:** `UserDetails`

Root authentication account used by Spring Security and higher-level user domains.

Key fields:

- `id`: internal numeric identifier
- `username`: unique login identifier
- `name`: display name
- `password`: encoded password
- `phone`: optional unique phone number
- `avatarImageId`: UUID reference to stored media
- `roles`: `Set<Role>` persisted in `user_roles`
- `userType`: derived textual summary of roles
- `enabled`: enable/disable switch
- `accountLocked`: explicit lock flag
- `accountExpiresAt`: account expiry timestamp
- `credentialsExpireAt`: password expiry timestamp
- `failedLoginAttempts`: failure counter
- `lockedAt`: lock timestamp
- `lastLoginAt`: last successful login timestamp
- `createdAt`, `updatedAt`: audit timestamps

Behavioral contract:

- `isAccountNonExpired()` fails when `accountExpiresAt` is in the past
- `isAccountNonLocked()` fails when `accountLocked` is `true`
- `isCredentialsNonExpired()` fails when `credentialsExpireAt` is in the past
- `isEnabled()` mirrors persisted `enabled`
- helper methods support lock/unlock, enable/disable, login tracking, and expiry updates

Persistence notes:

- soft-delete enabled through Hibernate `@SoftDelete`
- roles are stored in `user_roles`
- referenced by both `UserIdentityMap` and `RefreshToken`

### `UserIdentityMap`

**Kind:** entity  
**Table:** `user_identity_map`

Maps the internal `AppUser.id` to a public UUID used in JWTs and external API-facing identity lookups.

Key fields:

- `userId`: shared primary key
- `user`: one-to-one link to `AppUser`
- `publicId`: public UUID
- `active`: active/inactive access switch
- `createdAt`, `updatedAt`: audit timestamps

Behavioral contract:

- active mappings are the only ones resolvable by `getLocalUserId(...)`
- inactive mappings effectively disable authenticated access paths that rely on `public_uid`

Persistence notes:

- `@MapsId` enforces shared PK with `AppUser`
- migration `V14__user_identity_and_refresh_tokens.sql` adds a trigger that auto-creates the row for every inserted `app_users` record
- code comments mention UUID v7, but `AppUserService.saveAppUser(...)` currently generates `UUID.randomUUID()`

### `RefreshToken`

**Kind:** entity  
**Table:** `refresh_tokens`

Stores refresh-session state per device. Raw refresh tokens are never persisted; only SHA-256 hashes are stored.

Key fields:

- `id`
- `appUser`
- `tokenHash`
- `deviceId`
- `deviceName`
- `deviceType`
- `ipAddress`
- `userAgent`
- `createdAt`
- `expiresAt`
- `lastUsedAt`
- `revokedAt`
- `revokedReason`
- `replacedByTokenHash`

Behavioral contract:

- `isValid()` requires non-revoked and non-expired token
- `isExpired()` and `isRevoked()` expose token state checks
- `revoke(reason)` timestamps and records the revocation reason
- `markAsUsed()` updates `lastUsedAt`
- `isReplaced()` detects rotated tokens

Security notes:

- refresh tokens are device-bound through `deviceId`
- rotation preserves an audit chain via `replacedByTokenHash`
- reuse of a revoked token is treated as a security breach

### `Role`

Role enumeration currently contains:

- `ROLE_ADMIN`
- `ROLE_SELLER`
- `ROLE_CUSTOMER`
- `ROLE_DRIVER`
- `ROLE_ROOT`

These values are emitted directly as JWT authorities because `SecurityConfig` removes the default Spring `SCOPE_` prefix.

## Services

### `AppUserService`

Owns account persistence and authenticated profile operations.

Key operations:

- `loadUserByUsername(String)`
- `saveAppUser(AppUserRegisterReq, Set<Role>)`
- `findAppUserInfoById(Long)`
- `getAppUser(Long)`
- `changePassword(UUID, Long, ChangePasswordReq)`
- `getUpdatedAppUserInfo(Long, UpdateAppUserDto)`
- `UploadAndSetAvatar(MultipartFile, Long)`

Important rules:

- usernames must be unique
- passwords are encoded before persistence
- password change verifies old password and forbids reusing the current password
- password change triggers `logoutAllDevices(publicId)`

Implementation note:

- `saveAppUser(...)` calls `createUserIdentityMapCascad(...)`, but that method does not explicitly save through `UserIdentityMapRepository`; the database trigger from migration `V14` is what guarantees row creation

### `UserIdentityService`

Owns translation between public UUID identity and local numeric user identity.

Key operations:

- `findPublicIdByUserId(Long)`
- `findPublicIdForActiveUser(Long)`
- `getLocalUserId(UUID)`
- `extractUserIdFromJwt(Jwt)`
- `activateUser(UUID)`
- `deactivateUser(UUID)`
- `isUserActive(UUID)`
- `isUserActiveById(Long)`

Important rules:

- JWTs are expected to carry `public_uid`
- only active mappings are returned by `getLocalUserId(...)`
- cache `publicIdToLocalId` is used for repeated UUID-to-ID lookups
- activate/deactivate operations evict cache entries

### `AuthLoginService`

Authenticates username/password and issues a new access/refresh pair.

Flow summary:

1. Authenticate credentials with `AuthenticationManager`
2. Expect `AppUser` as the authenticated principal
3. Generate opaque refresh token and hash it
4. Resolve `publicId` from `UserIdentityService`
5. Persist `RefreshToken`
6. Issue JWT access token through `AccessTokenIssuer`
7. Update login metadata on `AppUser`
8. Force identity mapping to active

Default token settings:

- refresh token TTL: `14 days`
- access token TTL: `jwt.expiration` minutes from configuration

### `RefreshTokenService`

Owns refresh-token rotation, state validation, and breach handling.

Key rules enforced during refresh:

- request must include a refresh token
- token lookup is done by SHA-256 hash
- row is loaded with pessimistic lock to prevent concurrent refresh races
- `deviceId` must match when both sides provide it
- user must still be active, enabled, unlocked, non-expired, and have non-expired credentials
- replaced tokens are rejected
- expired tokens are rejected
- revoked-token reuse triggers a security incident

Security breach behavior:

- revoke all refresh tokens for the user
- deactivate the user identity mapping
- throw `RefreshTokenReuseException`

### `LogoutService`

Owns session revocation.

Operations:

- `logoutDevice(LogoutRequest)`: revoke the matching refresh token after device check
- `logoutAllDevices(UUID publicId)`: deactivate identity and revoke all refresh tokens
- `logoutSpecificDevice(UUID publicId, String deviceId)`: revoke all refresh tokens for one device

Operational note:

- `logoutAllDevices(...)` deactivates `UserIdentityMap.active`
- the next successful username/password login reactivates the identity via `AuthLoginService`

### `AccessTokenIssuer` and `JwtService`

Produce signed JWT access tokens.

JWT claims currently include:

- `iss`: configured issuer
- `iat`
- `exp`
- `sub`: current implementation uses `username`
- `scope`: space-separated role names
- `device_id`
- `public_uid`

Signing details:

- algorithm: `HS512`
- encoder: Spring `JwtEncoder`

### `RefreshTokenCleanupJob`

Scheduled cleanup for old refresh-token records.

Current behavior:

- runs daily at `03:00`
- deletes tokens with `expiresAt` or `revokedAt` older than `now - 60 days`

## HTTP Surface

### Authentication Endpoints

Base path: `/auth`

- `POST /auth/login`
  - request: `username`, `password`, `deviceId`
  - response: `TokenResponse`
- `POST /auth/refresh`
  - request: `refreshToken`, `deviceId`
  - response: `TokenResponse`
- `POST /auth/logout`
  - request: `refreshToken`, `deviceId`
  - response: `204 No Content`
- `POST /auth/logout/all`
  - requires authenticated JWT
  - reads `public_uid` from JWT
  - response: `204 No Content`

### Authenticated User Endpoints

Base path: `/api/user`

- `GET /api/user/profile`
- `PUT /api/user/profile`
- `POST /api/user/change-password`

All three resolve the current user from JWT `public_uid` through `UserIdentityService`.

## Exception Handling

### English

- Identity errors should always be returned through the bilingual platform envelope and must avoid leaking token hashes, account-state internals, or sensitive authentication details.
- `400 Bad Request`: use for malformed profile updates, invalid refresh or logout payloads, invalid username format, or password-change requests that violate local validation rules.
- `401 Unauthorized`: use for invalid credentials, expired or malformed JWTs, revoked refresh tokens, inactive identity mappings, locked accounts, expired accounts, or expired credentials.
- `403 Forbidden`: use when the caller is authenticated but does not have the authority required for the target identity operation.
- `404 Not Found`: use when the resolved user, profile record, or public-identity mapping cannot be found.
- `409 Conflict`: use for refresh-token reuse detection, duplicate username, phone, or public identity data, or other session-state conflicts.
- `500 Internal Server Error`: reserve for token-issuance failures, hashing failures, image-upload failures, or unexpected persistence or runtime issues.
- Current implementation note: refresh-token reuse already maps to `409 Conflict` via `RefreshTokenReuseException`, while the remaining identity failures still mix framework and generic exceptions.

### العربية

- يجب أن تعاد أخطاء الهوية دائماً عبر غلاف الأخطاء ثنائي اللغة، مع منع تسريب بصمات الرموز أو تفاصيل حالة الحساب أو أي معلومات حساسة تخص المصادقة.
- `400 طلب غير صحيح`: يستخدم عند وجود تحديث ملف شخصي مشوه، أو طلبات تحديث أو خروج غير صالحة، أو اسم مستخدم غير صالح، أو طلب تغيير كلمة مرور يخالف قواعد التحقق المحلية.
- `401 غير مصادق`: يستخدم عند وجود بيانات اعتماد غير صحيحة، أو JWT منتهي أو مشوه، أو رمز تحديث ملغى، أو خريطة هوية غير نشطة، أو حساب مقفول أو منتهي، أو بيانات اعتماد منتهية.
- `403 ممنوع`: يستخدم عندما يكون المستدعي مصادقاً لكنه لا يمتلك الصلاحية المطلوبة لتنفيذ عملية الهوية المطلوبة.
- `404 غير موجود`: يستخدم عندما لا يمكن العثور على المستخدم أو سجل الملف الشخصي أو خريطة الهوية العامة بعد عملية الحل.
- `409 تعارض`: يستخدم عند اكتشاف إعادة استخدام رمز التحديث، أو وجود اسم مستخدم أو هاتف أو هوية عامة مكررة، أو أي تعارض في حالة الجلسة.
- `500 خطأ داخلي في الخادم`: يحجز لفشل إصدار الرموز أو تجزئتها، أو فشل رفع الصور، أو مشاكل التخزين أو التشغيل غير المتوقعة.
- ملاحظة تنفيذية حالية: إعادة استخدام رمز التحديث تربط بالفعل مع `409 Conflict` عبر `RefreshTokenReuseException`، بينما بقية أخطاء الهوية ما زالت تمزج بين استثناءات الإطار والاستثناءات العامة.

## Security Integration

`SecurityConfig` sets the platform to stateless JWT resource-server mode.

Important characteristics:

- `/auth/**` is public
- identity APIs outside the allow-list require authentication
- OAuth2 resource server reads JWT bearer tokens
- JWT authorities come from claim `scope`
- no authority prefix is added by the JWT converter

## Persistence Summary

Primary tables involved in this domain:

- `app_users`
- `user_roles`
- `user_identity_map`
- `refresh_tokens`

Main relational structure:

- one `AppUser` to one `UserIdentityMap`
- one `AppUser` to many `RefreshToken`
- one `AppUser` to many role values in `user_roles`

## End-to-End Flows

### Login

1. Client posts username, password, and device UUID to `/auth/login`
2. Spring Security authenticates against `AppUserService.loadUserByUsername(...)`
3. `AuthLoginService` creates refresh token state and issues access token
4. JWT contains `public_uid`
5. Later authenticated requests translate `public_uid` back to local user ID

### Refresh

1. Client posts refresh token and device UUID to `/auth/refresh`
2. Service hashes token and locks the corresponding row
3. Active identity and account state are revalidated
4. Old token is revoked with `TOKEN_ROTATION`
5. New refresh token and new access token are returned

### Logout All Devices

1. Authenticated client calls `/auth/logout/all`
2. Service resolves `public_uid`
3. Identity mapping is deactivated
4. All refresh tokens are revoked
5. Existing refresh sessions stop working until a fresh login occurs

### Change Password

1. Authenticated client posts old and new passwords
2. Old password is verified
3. New password is encoded and stored
4. `logoutAllDevices(...)` is triggered
5. User must log in again to continue

## Design Constraints And Observations

- Public identity is intentionally decoupled from database IDs through `UserIdentityMap`
- Session state is server-side for refresh tokens, but access tokens remain stateless JWTs
- Identity activation is used as a coarse global access switch in addition to `AppUser` account flags
- Refresh-token rotation is strict and includes reuse detection
- The codebase currently mixes two mechanisms for identity-row creation: DB trigger and service-level object creation; the trigger is the reliable persisted path

## Improvement Areas

- Consolidate identity creation into one mechanism. Right now the system relies on both a DB trigger and a service-side object construction path.
- Align UUID strategy with the documented intent. Comments and migration describe UUID v7 behavior, while `AppUserService.saveAppUser(...)` currently uses `UUID.randomUUID()`.
- Make logout-all behavior clearer and safer. Deactivating `UserIdentityMap` on logout-all is coarse and can be surprising unless every fresh login is guaranteed to reactivate it.
- Revisit JWT claim consistency. Some parts of the system expect `public_uid`, while other domains still check for a `uid` claim first.
- Add stronger automated coverage for refresh-token rotation, reuse detection, and account-state transitions.
