# Offer UML

## Class Diagram

```mermaid
classDiagram
    class Offer {
        +Long id
        +String name
        +String description
        +OfferType offerType
        +BigDecimal discountValue
        +Instant startDate
        +Instant endDate
        +Boolean isStopped
        +boolean isLifecycleApplied
        +Long sellerId
        +Long version
        +statusAt(now)
        +suspend()
        +resume(now)
        +canActivate(now)
        +canResume(now)
        +markLifecycleApplied()
        +markLifecycleDeactivated()
    }

    class OfferType {
        <<enum>>
        PERCENTAGE
    }

    class OfferStatus {
        <<enum>>
        DRAFT
        ACTIVE
        SUSPENDED
        EXPIRED
    }

    class OfferVariantProj {
        +Long variantId
        +Long offerId
        +OfferType offerType
        +BigDecimal discountValue
        +Instant startDate
        +Instant endDate
        +Boolean isStopped
    }

    class Variant {
        +Long id
        +VariantPrice price
    }

    class VariantPrice {
        +BigDecimal basePrice
        +BigDecimal discountAmount
        +Long activeOfferId
        +OfferType offerType
        +Instant offerEndsAt
    }

    class OfferCalculator {
        +calculateDiscountAmount(type, basePrice, discountValue)
    }

    class OfferDomainEvent {
        <<interface>>
    }

    class OfferDomainEventPublisher {
        +publish(event)
    }

    class OfferEventListener {
        +handleOfferCreated(event)
        +handleOfferVariantsLinked(event)
        +handleOfferVariantsUnlinked(event)
        +handleOfferStopped(event)
        +handleOfferResumed(event)
        +handleOfferActivated(event)
        +handleOfferBatchActivated(event)
        +handleOfferBatchDeactivated(event)
    }

    class OfferCreatedEvent {
        +Long offerId
        +String offerName
        +Long sellerId
        +OfferType offerType
        +BigDecimal discountValue
    }

    class OfferVariantsLinkedEvent {
        +Long offerId
        +Long sellerId
        +Set~Long~ variantIds
    }

    class OfferVariantsUnlinkedEvent {
        +Long offerId
        +Long sellerId
        +Set~Long~ variantIds
    }

    class OfferStoppedEvent {
        +Long offerId
        +Long sellerId
        +Set~Long~ variantIds
    }

    class OfferResumedEvent {
        +Long offerId
        +Long sellerId
        +Set~Long~ variantIds
        +OfferStatus currentStatus
    }

    class OfferActivatedEvent {
        +Long offerId
        +Long sellerId
        +Set~Long~ variantIds
    }

    class OfferBatchActivatedEvent {
        +Set~Long~ offerIds
        +Set~Long~ impactedVariantIds
        +Instant processedAt
    }

    class OfferBatchDeactivatedEvent {
        +Set~Long~ offerIds
        +Set~Long~ impactedVariantIds
        +Instant processedAt
    }

    Offer "0..*" --> "0..*" Variant : targets
    Variant "1" --> "1" VariantPrice : embeds
    Offer --> OfferType
    Offer --> OfferStatus
    OfferReassignmentFacade ..> OfferVariantProj : uses
    OfferReassignmentFacade ..> OfferCalculator : calculates
    OfferCommandService ..> OfferDomainEventPublisher : publishes
    OfferManagementFacade ..> OfferDomainEventPublisher : publishes
    OfferEventListener ..> OfferCreatedEvent : handles
    OfferEventListener ..> OfferVariantsLinkedEvent : handles
    OfferEventListener ..> OfferVariantsUnlinkedEvent : handles
    OfferEventListener ..> OfferStoppedEvent : handles
    OfferEventListener ..> OfferResumedEvent : handles
    OfferEventListener ..> OfferActivatedEvent : handles
    OfferEventListener ..> OfferBatchActivatedEvent : handles
    OfferEventListener ..> OfferBatchDeactivatedEvent : handles
    OfferDomainEventPublisher ..> OfferDomainEvent : publishes
    OfferCreatedEvent ..|> OfferDomainEvent
    OfferVariantsLinkedEvent ..|> OfferDomainEvent
    OfferVariantsUnlinkedEvent ..|> OfferDomainEvent
    OfferStoppedEvent ..|> OfferDomainEvent
    OfferResumedEvent ..|> OfferDomainEvent
    OfferActivatedEvent ..|> OfferDomainEvent
    OfferBatchActivatedEvent ..|> OfferDomainEvent
    OfferBatchDeactivatedEvent ..|> OfferDomainEvent
```

## Service Dependency Diagram

```mermaid
flowchart LR
    OfferController["OfferController"] --> OfferCommandService["OfferCommandService"]

    OfferCommandService --> OfferRepository["OfferRepository"]
    OfferCommandService --> VariantService["VariantService"]
    OfferCommandService --> OfferReassignmentService["OfferReassignmentService"]
    OfferCommandService --> OfferManagementFacade["OfferManagementFacade"]
    OfferCommandService --> ProductCacheService["ProductCacheService"]
    OfferCommandService --> OfferDomainEventPublisher["OfferDomainEventPublisher"]

    OfferManagementFacade --> OfferRepository
    OfferManagementFacade --> VariantService
    OfferManagementFacade --> ProductCacheService
    OfferManagementFacade --> OfferDomainEventPublisher

    OfferReassignmentService --> OfferRepository
    OfferReassignmentService --> VariantService
    OfferReassignmentService --> OfferManagementFacade
    OfferReassignmentService --> OfferReassignmentFacade["OfferReassignmentFacade"]

    OfferReassignmentFacade --> OfferRepository
    OfferReassignmentFacade --> VariantRepository["VariantRepository"]

    OfferScheduler["OfferScheduler"] --> OfferReassignmentService
    OfferDomainEventPublisher --> ApplicationEventPublisher["ApplicationEventPublisher"]
    ApplicationEventPublisher -. dispatches .-> OfferEventListener["OfferEventListener"]
    OfferEventListener -. handles .-> OfferEvents["Offer*Event"]
```

## Create Offer Sequence

```mermaid
sequenceDiagram
    actor Seller
    participant OfferController
    participant OfferCommandService
    participant OfferRepository
    participant OfferDomainEventPublisher

    Seller->>OfferController: POST /api/admin/offers
    OfferController->>OfferCommandService: createOffer(sellerId, dto)
    OfferCommandService->>OfferCommandService: build Offer aggregate
    OfferCommandService->>OfferRepository: save(offer)
    OfferRepository-->>OfferCommandService: Offer
    OfferCommandService->>OfferDomainEventPublisher: publish(OfferCreatedEvent)
    OfferCommandService-->>OfferController: Offer
    OfferController-->>Seller: 201 Created
```

## Add Variants To Offer Sequence

```mermaid
sequenceDiagram
    actor Seller
    participant OfferController
    participant OfferCommandService
    participant OfferManagementFacade
    participant OfferRepository
    participant VariantService
    participant ProductCacheService
    participant OfferReassignmentService
    participant OfferDomainEventPublisher

    Seller->>OfferController: POST /{offerId}/variants
    OfferController->>OfferCommandService: addVariants(sellerId, offerId, variantIds)
    OfferCommandService->>OfferManagementFacade: linkVariantsToOffer(...)
    OfferManagementFacade->>OfferRepository: findByIdAndSellerId(...)
    OfferRepository-->>OfferManagementFacade: Offer
    OfferManagementFacade->>VariantService: countBySellerIdAndIdIn(...)
    VariantService-->>OfferManagementFacade: owned count
    OfferManagementFacade->>OfferRepository: linkBatchIgnore(...)
    OfferManagementFacade->>OfferRepository: bumpOfferVersion(...)
    OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferVariantsLinkedEvent)
    OfferManagementFacade-->>OfferCommandService: Offer
    OfferCommandService->>ProductCacheService: evictImpactedProductsByVariantIds(...)
    alt offer active now
        OfferCommandService->>OfferReassignmentService: reassignOfferToVariantBatch(variantIds)
    end
    OfferCommandService-->>OfferController: void
    OfferController-->>Seller: 200 OK
```

## Offer Reassignment Sequence

```mermaid
sequenceDiagram
    participant OfferReassignmentService
    participant OfferRepository
    participant VariantService
    participant OfferReassignmentFacade
    participant VariantRepository

    OfferReassignmentService->>OfferRepository: findOffersProj(variantIds, now)
    OfferRepository-->>OfferReassignmentService: OfferVariantProj list
    OfferReassignmentService->>VariantService: findAllByIds(batchIds)
    VariantService-->>OfferReassignmentService: Variant list
    OfferReassignmentService->>OfferReassignmentFacade: reassignOfferToVariantBatchHelper(variants, varOffersMap)
    loop each variant
        OfferReassignmentFacade->>OfferReassignmentFacade: choose best offer by discount
        alt best offer exists
            OfferReassignmentFacade->>OfferReassignmentFacade: applyOfferForced(variant, bestOffer)
        else no active offer
            OfferReassignmentFacade->>OfferReassignmentFacade: clearOfferForced(variant)
        end
    end
    OfferReassignmentFacade->>VariantRepository: saveAllAndFlush(variants)
```

## Scheduled Lifecycle Sequence

```mermaid
sequenceDiagram
    participant OfferScheduler
    participant OfferReassignmentService
    participant OfferManagementFacade
    participant OfferRepository
    participant VariantService
    participant OfferDomainEventPublisher

    alt activation cycle
        OfferScheduler->>OfferReassignmentService: activateAndReassignOffers()
        OfferReassignmentService->>OfferManagementFacade: batchActivateOffersNow()
        OfferManagementFacade->>OfferRepository: findOfferIdsToActivate(now)
        OfferManagementFacade->>OfferRepository: markLifecycleAppliedByIds(offerIds, true)
        OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferBatchActivatedEvent)
        OfferManagementFacade-->>OfferReassignmentService: impactedVariants
        OfferReassignmentService->>OfferReassignmentService: reassignOfferToVariantBatch(impactedVariants)
    else deactivation cycle
        OfferScheduler->>OfferReassignmentService: deactivateAndReassignOffers()
        OfferReassignmentService->>OfferManagementFacade: batchDeactivateOffersNow()
        OfferManagementFacade->>OfferRepository: findOfferIdsToDeactivate(now)
        OfferManagementFacade->>VariantService: removeOffersByIds(impactedVariants)
        OfferManagementFacade->>OfferRepository: markLifecycleAppliedByIds(offerIds, false)
        OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferBatchDeactivatedEvent)
        OfferManagementFacade-->>OfferReassignmentService: impactedVariants
        OfferReassignmentService->>OfferReassignmentService: reassignOfferToVariantBatch(impactedVariants)
    end
```

## Offer Lifecycle Command Sequence

```mermaid
sequenceDiagram
    actor Seller
    participant OfferController
    participant OfferCommandService
    participant OfferManagementFacade
    participant OfferRepository
    participant VariantService
    participant ProductCacheService
    participant OfferReassignmentService
    participant OfferDomainEventPublisher

    alt stop offer
        Seller->>OfferController: POST /{offerId}/stop
        OfferController->>OfferCommandService: stopOffer(sellerId, offerId)
        OfferCommandService->>OfferManagementFacade: stopOffer(...)
        OfferManagementFacade->>OfferRepository: findByIdAndSellerId(...)
        OfferManagementFacade->>VariantService: findIdsByOfferId(offerId)
        OfferManagementFacade->>VariantService: removeOffersByIds(variantIds)
        OfferManagementFacade->>OfferManagementFacade: suspend()
        OfferManagementFacade->>OfferRepository: save(offer)
        OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferStoppedEvent)
        OfferCommandService->>ProductCacheService: evictImpactedProductsByVariantIds(variantIds)
        OfferCommandService->>OfferReassignmentService: reassignOfferToVariantBatch(variantIds)
    else resume offer
        Seller->>OfferController: POST /{offerId}/resume
        OfferController->>OfferCommandService: resumeOffer(sellerId, offerId)
        OfferCommandService->>OfferManagementFacade: resumeOffer(...)
        OfferManagementFacade->>OfferManagementFacade: resume(now) and statusAt(now)
        OfferManagementFacade->>OfferRepository: save(offer)
        OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferResumedEvent)
        OfferCommandService->>ProductCacheService: evictImpactedProductsByVariantIds(variantIds)
        OfferCommandService->>OfferReassignmentService: reassignOfferToVariantBatch(variantIds)
    else activate now
        Seller->>OfferController: POST /{offerId}/activate
        OfferController->>OfferCommandService: activateOfferNow(sellerId, offerId)
        OfferCommandService->>OfferManagementFacade: startOfferNow(...)
        OfferManagementFacade->>OfferManagementFacade: resume(now), setStartDate(now), markLifecycleApplied()
        OfferManagementFacade->>OfferRepository: save(offer)
        OfferManagementFacade->>OfferDomainEventPublisher: publish(OfferActivatedEvent)
        OfferCommandService->>ProductCacheService: evictImpactedProductsByVariantIds(variantIds)
        OfferCommandService->>OfferReassignmentService: reassignOfferToVariantBatch(variantIds)
    end
```

## Offer Event Flow

```mermaid
flowchart LR
    Create["OfferCommandService.createOffer"] --> Created["OfferCreatedEvent"]
    Link["OfferManagementFacade.linkVariantsToOffer"] --> Linked["OfferVariantsLinkedEvent"]
    Unlink["OfferManagementFacade.detachVariantsFromOffer"] --> Unlinked["OfferVariantsUnlinkedEvent"]
    Stop["OfferManagementFacade.stopOffer"] --> Stopped["OfferStoppedEvent"]
    Resume["OfferManagementFacade.resumeOffer"] --> Resumed["OfferResumedEvent"]
    Activate["OfferManagementFacade.startOfferNow"] --> Activated["OfferActivatedEvent"]
    BatchOn["OfferManagementFacade.batchActivateOffersNow"] --> BatchActivated["OfferBatchActivatedEvent"]
    BatchOff["OfferManagementFacade.batchDeactivateOffersNow"] --> BatchDeactivated["OfferBatchDeactivatedEvent"]

    Created --> Publisher["OfferDomainEventPublisher"]
    Linked --> Publisher
    Unlinked --> Publisher
    Stopped --> Publisher
    Resumed --> Publisher
    Activated --> Publisher
    BatchActivated --> Publisher
    BatchDeactivated --> Publisher

    Publisher --> SpringEvents["ApplicationEventPublisher"]
    SpringEvents --> Listener["OfferEventListener"]
    Listener --> AfterCommit["AFTER_COMMIT handlers"]
```

## Offer State Diagram

```mermaid
stateDiagram-v2
    [*] --> Draft
    Draft --> Active : startDate reached and not stopped
    Active --> Suspended : suspend()
    Suspended --> Active : resume(now)
    Draft --> Suspended : suspend()
    Active --> Expired : endDate passed
    Suspended --> Expired : endDate passed
```

## Effective Pricing Rule Diagram

```mermaid
flowchart TD
    A["Variant has candidate offers"] --> B["Calculate discount amount for each offer"]
    B --> C{"Best discount exists?"}
    C -- "No" --> D["Clear VariantPrice active offer state"]
    C -- "Yes" --> E["Choose highest discount"]
    E --> F{"Tie?"}
    F -- "No" --> G["Apply chosen offer"]
    F -- "Yes" --> H["Choose later endDate"]
    H --> G
    G --> I["Write discountAmount, activeOfferId, offerType, offerEndsAt"]
```
