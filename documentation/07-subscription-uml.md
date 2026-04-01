# Subscription UML

## Class Diagram

```mermaid
classDiagram
    class Plan {
        +Long id
        +String code
        +String name
        +BigDecimal price
        +boolean paid
        +long periodDays
        +int level
        +int trialDays
        +boolean defaultFree
        +boolean active
        +Map~LimitType,LimitValue~ limits
        +getPeriod()
        +isTrial()
        +getTrialPeriod()
        +getLimit(type)
    }

    class Subscription {
        +Long id
        +Long userId
        +SubscriptionStatus status
        +Instant startAt
        +Instant endAt
        +Instant deletedAt
        +Map~LimitType,UsageValue~ usages
        +Instant graceAppliedAt
        +Instant lastRenewedAt
        +Long nextPlanId
        +isGraced()
        +isDeleted()
        +isExpired(now)
        +isCurrentlyValid(now)
        +canConsume(type, amount)
        +consume(type, amount)
        +resetUsages()
        +softDelete()
        +markRenewedAt(now)
    }

    class LimitType {
        <<enumeration>>
        PRODUCTS
        ORDERS
        STORAGE_MB
    }

    class LimitValue {
        +Integer max
        +isUnlimited()
        +canConsume(used, amount)
        +unlimited()
        +of(max)
    }

    class UsageValue {
        +long used
        +zero()
        +add(amount)
        +increment(amount)
        +reset()
    }

    class SubscriptionStatus {
        <<enumeration>>
        FREE
        TRAIL
        PAID
        PAY_PENDING
    }

    Plan "1" --> "0..*" Subscription : subscribed as
    Plan --> LimitType
    Subscription --> SubscriptionStatus
    Subscription --> LimitType
```

## Service Dependency Diagram

```mermaid
flowchart LR
    PlanController["PlanController"] --> PlanService["PlanService"]

    SubscriptionController["SubscriptionController"] --> SubscriptionService["SubscriptionService"]
    SubscriptionController --> UserIdentityService["UserIdentityService"]

    SubPaymentController["SubPaymentController"] --> SubPaymentService["SubPaymentService"]
    SubPaymentController --> SubscriptionRepository["SubscriptionRepository"]

    PlanService --> PlanRepository["PlanRepository"]

    SubscriptionService --> SubscriptionRepository
    SubscriptionService --> PlanService
    SubscriptionService --> EventPublisher["ApplicationEventPublisher"]
```

## Current Or Go Free Sequence

```mermaid
sequenceDiagram
    participant User
    participant SubscriptionController
    participant SubscriptionService
    participant SubscriptionRepository
    participant PlanService
    participant EventPublisher

    User->>SubscriptionController: GET /api/subscriptions/current
    SubscriptionController->>SubscriptionService: getCurrentOrGoFree(userId)
    SubscriptionService->>SubscriptionRepository: findCurrentByUserId(userId)
    alt current exists
        SubscriptionRepository-->>SubscriptionService: current subscription
        SubscriptionService-->>SubscriptionController: current subscription
    else no current
        SubscriptionService->>SubscriptionRepository: findLatestByUserId(userId)
        alt latest paid and grace available
            SubscriptionService->>SubscriptionService: extend by 2 days, mark PAY_PENDING
            SubscriptionService->>EventPublisher: publish PayPendingSubscription
            SubscriptionService->>SubscriptionRepository: save(subscription)
            SubscriptionRepository-->>SubscriptionService: graced subscription
        else latest free and expired
            SubscriptionService->>SubscriptionService: renew in place, reset usages
            SubscriptionService->>SubscriptionRepository: save(subscription)
            SubscriptionRepository-->>SubscriptionService: renewed free subscription
        else fallback
            SubscriptionService->>PlanService: getDefFreePlan()
            PlanService-->>SubscriptionService: default free plan
            SubscriptionService->>SubscriptionRepository: save(new FREE subscription)
            SubscriptionRepository-->>SubscriptionService: free subscription
        end
        SubscriptionService-->>SubscriptionController: effective subscription
    end
    SubscriptionController-->>User: 200 OK
```

## Admin Upgrade Sequence

```mermaid
sequenceDiagram
    participant Admin
    participant SubscriptionController
    participant SubscriptionService
    participant PlanService
    participant SubscriptionRepository

    Admin->>SubscriptionController: POST /api/subscriptions/admin/upgrade
    SubscriptionController->>SubscriptionService: upgradeOrSameNow(userId, newPlanId)
    SubscriptionService->>PlanService: getByIdAndActiveTrue(newPlanId)
    PlanService-->>SubscriptionService: Plan
    SubscriptionService->>SubscriptionRepository: findByUserIdAndDeletedAtIsNullAndEndAtGreaterThan(userId, now)
    SubscriptionRepository-->>SubscriptionService: active/future subscriptions
    SubscriptionService->>SubscriptionService: softDelete existing subscriptions
    SubscriptionService->>SubscriptionRepository: save(new PAID subscription)
    SubscriptionRepository-->>SubscriptionService: upgraded subscription
    SubscriptionService-->>SubscriptionController: Subscription
    SubscriptionController-->>Admin: 200 OK
```

## Quota Consumption Sequence

```mermaid
sequenceDiagram
    participant User
    participant SubscriptionController
    participant SubscriptionService
    participant Subscription
    participant SubscriptionRepository

    User->>SubscriptionController: POST /api/subscriptions/consume
    SubscriptionController->>SubscriptionService: consume(userId, type, amount)
    SubscriptionService->>SubscriptionService: getCurrentOrGoFree(userId)
    SubscriptionService->>Subscription: canConsume(type, amount)
    alt allowed
        SubscriptionService->>Subscription: consume(type, amount)
        SubscriptionService->>SubscriptionRepository: save(subscription)
        SubscriptionController-->>User: 204 No Content
    else denied
        Subscription-->>SubscriptionService: LimitExceededException
        SubscriptionController-->>User: error
    end
```

## State Diagram For Subscription Lifecycle

```mermaid
stateDiagram-v2
    [*] --> FREE
    FREE --> FREE : renew expired free in place
    FREE --> PAID : admin purchase or upgrade
    PAID --> PAY_PENDING : paid expired and grace applied
    PAY_PENDING --> PAID : future payment recovery flow
    PAY_PENDING --> FREE : fallback after grace path no longer valid
    PAID --> Deleted : cancel or upgrade replacement
    FREE --> Deleted : cancel
```

## ER View

```mermaid
flowchart LR
    plans["plans"]
    subscriptions["subscriptions"]

    plans --> subscriptions
    subscriptions -.-> plans
```
