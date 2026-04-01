# App User UML

## Class Diagram

```mermaid
classDiagram
    class AppUser {
        +Long id
        +String username
        +String name
        +String password
        +String phone
        +UUID avatarImageId
        +Set~Role~ roles
        +String userType
        +boolean enabled
        +boolean accountLocked
        +Instant accountExpiresAt
        +Instant credentialsExpireAt
        +int failedLoginAttempts
        +Instant lockedAt
        +Instant lastLoginAt
        +lockAccount()
        +unlockAccount()
        +incrementFailedLoginAttempts()
        +resetFailedLoginAttempts()
        +recordSuccessfulLogin()
        +disable()
        +enable()
        +addRole(role)
    }

    class Customer {
        +Long id
    }

    class Seller {
        +Long id
        +Long appUserAddressId
        +addSellerRole()
    }

    class AppUserAddress {
        +Long id
        +Point location
        +String buildingNumber
        +String apartmentNumber
        +String floor
        +String additionalInfo
        +Boolean isPrimary
        +String addressPhone
        +Instant createdAt
        +Instant updatedAt
        +getLatitude()
        +getLongitude()
        +setLocation(lat, lng)
        +hasLocation()
    }

    class Address {
        <<external domain>>
    }

    class UserIdentityMap {
        +Long userId
        +UUID publicId
        +boolean active
        +Instant createdAt
        +Instant updatedAt
        +isActive()
    }

    class RefreshToken {
        <<identity/auth>>
    }

    AppUser "1" --> "0..1" Customer : specialized as
    AppUser "1" --> "0..1" Seller : specialized as
    AppUser "1" --> "0..*" AppUserAddress : owns
    Address "1" --> "0..*" AppUserAddress : reused by
    AppUser "1" --> "1" UserIdentityMap : mapped to
    AppUser "1" --> "0..*" RefreshToken : authenticates with
```

## Service Dependency Diagram

```mermaid
flowchart LR
    CustomerController["CustomerController"] --> CustomerService["CustomerService"]
    SellerController["SellerController"] --> SellerService["SellerService"]
    UserAddressController["UserAddressController"] --> AppUserAddressService["AppUserAddressService"]

    CustomerService --> AppUserService["AppUserService"]
    CustomerService --> CustomerRepository["CustomerRepository"]
    CustomerService --> WalletService["WalletService"]
    CustomerService --> AuthLoginService["AuthLoginService"]

    SellerService --> CustomerService
    SellerService --> SellerRepository["SellerRepository"]
    SellerService --> AppUserAddressService
    SellerService --> StoreService["StoreService"]
    SellerService --> MerchantBalanceService["MerchantBalanceService"]
    SellerService --> AuthLoginService

    AppUserAddressService --> AddressService["AddressService"]
    AppUserAddressService --> AppUserService
    AppUserAddressService --> AppUserAddressRepository["AppUserAddressRepository"]

    AppUserService --> AppUserRepository["AppUserRepository"]
    AppUserService --> UserIdentityService["UserIdentityService"]
    AppUserService --> MediaService["MediaService"]
    AppUserService --> LogoutService["LogoutService"]

    AuthLoginService --> UserIdentityService
    AuthLoginService --> RefreshTokenRepository["RefreshTokenRepository"]
    AuthLoginService --> AccessTokenIssuer["AccessTokenIssuer"]
```

## Customer Registration Sequence

```mermaid
sequenceDiagram
    actor Client
    participant CustomerController
    participant CustomerService
    participant AppUserService
    participant AppUserRepository
    participant UserIdentityService
    participant CustomerRepository
    participant WalletService
    participant AuthLoginService

    Client->>CustomerController: POST /api/customer/register
    CustomerController->>CustomerService: createCustomer(request)
    CustomerService->>AppUserService: saveAppUser(request, ROLE_CUSTOMER)
    AppUserService->>AppUserRepository: save(appUser)
    AppUserRepository-->>AppUserService: saved AppUser
    AppUserService->>UserIdentityService: createUserIdentityMapCascad(appUser, publicId, true)
    UserIdentityService-->>AppUserService: mapping created
    AppUserService-->>CustomerService: saved AppUser
    CustomerService->>CustomerRepository: save(Customer with MapsId)
    CustomerRepository-->>CustomerService: saved Customer
    CustomerService->>WalletService: createWallet(appUserId)
    WalletService-->>CustomerService: wallet created
    CustomerService->>AuthLoginService: getAccess(deviceId, appUser)
    AuthLoginService-->>CustomerService: TokenResponse
    CustomerService-->>CustomerController: TokenResponse
    CustomerController-->>Client: 201 Created
```

## Seller Upgrade Sequence

```mermaid
sequenceDiagram
    actor Client
    participant SellerController
    participant UserIdentityService
    participant SellerService
    participant CustomerService
    participant SellerRepository
    participant AppUserAddressService
    participant StoreService
    participant MerchantBalanceService
    participant AuthLoginService

    Client->>SellerController: POST /api/seller/register
    SellerController->>UserIdentityService: extractUserIdFromJwt(jwt)
    UserIdentityService-->>SellerController: customerId
    SellerController->>SellerService: createSeller(customerId, deviceId, dto)
    SellerService->>CustomerService: findCustomerById(customerId)
    CustomerService-->>SellerService: Customer(AppUser)
    SellerService->>SellerRepository: existsByAppUserId(appUser.id)
    SellerRepository-->>SellerService: false
    SellerService->>SellerRepository: save(Seller)
    alt dto.addressDto exists
        SellerService->>AppUserAddressService: addOrUpdateAddressToUser(appUser.id, addressDto)
        AppUserAddressService-->>SellerService: AppUserAddress
    else existing address id provided
        SellerService->>SellerService: set appUserAddressId
    end
    SellerService->>StoreService: createOrUpdate(seller.id, storeDto)
    SellerService->>MerchantBalanceService: createMerchantBalance(appUser.id)
    SellerService->>AuthLoginService: getAccess(deviceId, appUser)
    AuthLoginService-->>SellerService: TokenResponse
    SellerService-->>SellerController: TokenResponse
    SellerController-->>Client: 201 Created
```

## User Address Management Sequence

```mermaid
sequenceDiagram
    actor Client
    participant UserAddressController
    participant AppUserAddressService
    participant AddressService
    participant AppUserService
    participant AppUserAddressRepository

    Client->>UserAddressController: POST /api/user/addresses/{addressId}
    UserAddressController->>AppUserAddressService: addOrUpdateAddressToUser(appUserId, req)
    AppUserAddressService->>AddressService: findAddressById(req.addressId)
    AddressService-->>AppUserAddressService: Address
    AppUserAddressService->>AppUserService: getAppUser(appUserId)
    AppUserService-->>AppUserAddressService: AppUser
    AppUserAddressService->>AppUserAddressRepository: findByAppUserAndAddress(appUser, address)
    alt relation exists
        AppUserAddressRepository-->>AppUserAddressService: existing link
    else relation missing
        AppUserAddressService->>AppUserAddressService: create new AppUserAddress
    end
    opt req.isPrimary = true
        AppUserAddressService->>AppUserAddressRepository: unsetPrimaryAddressForUser(appUserId)
    end
    AppUserAddressService->>AppUserAddressRepository: save(userAddress)
    AppUserAddressRepository-->>AppUserAddressService: saved link
    AppUserAddressService-->>UserAddressController: AppUserAddress
    UserAddressController-->>Client: 200 OK
```

## State Diagram For Account Status

```mermaid
stateDiagram-v2
    [*] --> Enabled
    Enabled --> Locked : lockAccount()
    Locked --> Enabled : unlockAccount()
    Enabled --> Disabled : disable()
    Disabled --> Enabled : enable()
    Enabled --> Expired : accountExpiresAt passed
    Enabled --> CredentialsExpired : credentialsExpireAt passed
    Expired --> Enabled : setAccountExpiration(future)
    CredentialsExpired --> Enabled : setPasswordExpiration(future)
```

## ER-Style Relationship View

```mermaid
flowchart TB
    app_users["app_users"]
    user_roles["user_roles"]
    customers["customers"]
    sellers["sellers"]
    app_user_address["app_user_address"]
    user_identity_map["user_identity_map"]
    addresses["addresses"]

    app_users --> user_roles
    app_users --> customers
    app_users --> sellers
    app_users --> app_user_address
    addresses --> app_user_address
    app_users --> user_identity_map
```
