# Address UML

## Class Diagram

```mermaid
classDiagram
    class Country {
        +Long id
        +String name
        +String code
        +String phoneCode
        +Instant createdAt
        +Instant updatedAt
    }

    class State {
        +Long id
        +String name
        +Polygon geom
        +Point centroid
        +Instant createdAt
        +Instant updatedAt
        +setLocation(latitude, longitude)
    }

    class City {
        +Long id
        +String name
        +Polygon geom
        +Point centroid
        +Instant createdAt
        +Instant updatedAt
        +setLocation(latitude, longitude)
        +hasLocation()
        +distanceTo(other)
    }

    class Street {
        +Long id
        +String name
        +Instant createdAt
        +Instant updatedAt
    }

    class Address {
        +Long id
        +String name
        +Instant createdAt
        +Instant updatedAt
    }

    class AppUserAddress {
        <<external app-user domain>>
        +Long id
        +Point location
        +Boolean isPrimary
        +String buildingNumber
        +String apartmentNumber
        +String floor
        +String additionalInfo
        +String addressPhone
    }

    Country "1" --> "0..*" State : contains
    State "1" --> "0..*" City : contains
    City "1" --> "0..*" Street : contains
    Street "1" --> "0..*" Address : contains
    Address "1" --> "0..*" AppUserAddress : linked by
```

## Service Dependency Diagram

```mermaid
flowchart LR
    PublicAddressController["PublicAddressController"] --> AddressService["AddressService"]
    PublicAddressController --> CountryService["CountryService"]
    PublicAddressController --> StateService["StateService"]
    PublicAddressController --> CityService["CityService"]
    PublicAddressController --> StreetService["StreetService"]

    AdminAddressController["AdminAddressController"] --> AddressService
    AdminAddressController --> CountryService
    AdminAddressController --> StateService
    AdminAddressController --> CityService
    AdminAddressController --> StreetService
    AdminAddressController --> AppUserAddressService["AppUserAddressService"]
    AdminAddressController --> UserIdentityService["UserIdentityService"]

    CountryService --> CountryRepository["CountryRepository"]

    StateService --> StateRepository["StateRepository"]
    StateService --> CountryRepository
    StateService --> StateGeoImportService["StateGeoImportService"]

    CityService --> CityRepository["CityRepository"]
    CityService --> StateRepository
    CityService --> CityGeoImportService["CityGeoImportService"]

    StreetService --> StreetRepository["StreetRepository"]
    StreetService --> CityRepository

    AddressService --> AddressRepository["AddressRepository"]
    AddressService --> StreetRepository

    StateGeoImportService --> GeoPythonState["geo-tools/import_state_polygon.py"]
    CityGeoImportService --> GeoPythonCity["geo-tools/import_city_polygon.py"]
```

## Public Lookup Sequence

```mermaid
sequenceDiagram
    participant Client
    participant PublicAddressController
    participant CountryService
    participant StateService
    participant CityService
    participant StreetService
    participant AddressService

    Client->>PublicAddressController: GET /locations/countries
    PublicAddressController->>CountryService: findAllCountries()
    CountryService-->>PublicAddressController: CountryDto[]
    PublicAddressController-->>Client: countries

    Client->>PublicAddressController: GET /locations/states?countryId=...
    PublicAddressController->>StateService: findStatesByCountry(countryId)
    StateService-->>PublicAddressController: StateDto[]
    PublicAddressController-->>Client: states

    Client->>PublicAddressController: GET /locations/cities?stateId=...
    PublicAddressController->>CityService: findCitiesByState(stateId)
    CityService-->>PublicAddressController: CityDto[]
    PublicAddressController-->>Client: cities

    Client->>PublicAddressController: GET /locations/streets?cityId=...
    PublicAddressController->>StreetService: findStreetsByCity(cityId)
    StreetService-->>PublicAddressController: StreetDto[]
    PublicAddressController-->>Client: streets

    Client->>PublicAddressController: GET /locations/addresses?streetId=...
    PublicAddressController->>AddressService: findAddressDtoByStreet(streetId)
    AddressService-->>PublicAddressController: AddressWithStreetDto[]
    PublicAddressController-->>Client: addresses
```

## State Geo-Import Sequence

```mermaid
sequenceDiagram
    participant Admin
    participant AdminAddressController
    participant StateService
    participant CountryRepository
    participant StateGeoImportService
    participant StateRepository

    Admin->>AdminAddressController: POST /api/admin/address/states
    AdminAddressController->>StateService: create(countryId, dto)
    StateService->>CountryRepository: existsById(dto.countryId)
    CountryRepository-->>StateService: true
    StateService->>StateGeoImportService: importState(dto)
    StateGeoImportService->>StateGeoImportService: run python import_state_polygon.py
    StateGeoImportService-->>StateService: exit code 0
    StateService->>StateRepository: findStateByCountryAndName(dto.stateName, dto.countryId)
    StateRepository-->>StateService: State
    StateService-->>AdminAddressController: State
    AdminAddressController-->>Admin: 200 OK
```

## Admin User-Address Assignment Sequence

```mermaid
sequenceDiagram
    participant Admin
    participant AdminAddressController
    participant UserIdentityService
    participant AppUserAddressService
    participant AddressService

    Admin->>AdminAddressController: POST /users/{userId}/addresses
    AdminAddressController->>UserIdentityService: extractUserIdFromJwt(jwt)
    AdminAddressController->>AppUserAddressService: addOrUpdateAddressToUser(userId, req)
    AppUserAddressService->>AddressService: findAddressById(req.addressId)
    AddressService-->>AppUserAddressService: Address
    AppUserAddressService-->>AdminAddressController: AppUserAddress
    AdminAddressController-->>Admin: 200 OK
```

## State Diagram For Hierarchy Growth

```mermaid
stateDiagram-v2
    [*] --> CountryCreated
    CountryCreated --> StateCreated : create state
    StateCreated --> CityCreated : create city
    CityCreated --> StreetCreated : create street
    StreetCreated --> AddressCreated : create address
    AddressCreated --> UserLinked : link through AppUserAddress
```

## ER View

```mermaid
flowchart LR
    countries["countries"]
    states["states"]
    cities["cities"]
    streets["streets"]
    address["address"]
    app_user_address["app_user_address"]

    countries --> states
    states --> cities
    cities --> streets
    streets --> address
    address --> app_user_address
```
