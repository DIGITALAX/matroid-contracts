import {
  GandaDeactivated as GandaDeactivatedEvent,
  GandaRegistered as GandaRegisteredEvent,
  GandaUpdated as GandaUpdatedEvent,
  ReactionSubmitted as ReactionSubmittedEvent
} from "../generated/GandaRegistry/GandaRegistry"
import {
  GandaDeactivated,
  GandaRegistered,
  GandaUpdated,
  ReactionSubmitted
} from "../generated/schema"

export function handleGandaDeactivated(event: GandaDeactivatedEvent): void {
  let entity = new GandaDeactivated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.ganadaId = event.params.ganadaId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleGandaRegistered(event: GandaRegisteredEvent): void {
  let entity = new GandaRegistered(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.ganadaId = event.params.ganadaId
  entity.creator = event.params.creator
  entity.uri = event.params.uri

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleGandaUpdated(event: GandaUpdatedEvent): void {
  let entity = new GandaUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.ganadaId = event.params.ganadaId
  entity.uri = event.params.uri

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleReactionSubmitted(event: ReactionSubmittedEvent): void {
  let entity = new ReactionSubmitted(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  )
  entity.ganadaId = event.params.ganadaId
  entity.reactionId = event.params.reactionId
  entity.reviewer = event.params.reviewer

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
