import {
  DesignerDeactivated as DesignerDeactivatedEvent,
  DesignerInvited as DesignerInvitedEvent,
  DesignerURI as DesignerURIEvent,
  ReactionPacksUpdated as ReactionPacksUpdatedEvent,
} from "../generated/GandaDesigners/GandaDesigners"
import {
  DesignerDeactivated,
  DesignerInvited,
  DesignerURI,
  ReactionPacksUpdated,
} from "../generated/schema"

export function handleDesignerDeactivated(
  event: DesignerDeactivatedEvent,
): void {
  let entity = new DesignerDeactivated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.designerId = event.params.designerId
  entity.inviter = event.params.inviter

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleDesignerInvited(event: DesignerInvitedEvent): void {
  let entity = new DesignerInvited(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.designer = event.params.designer
  entity.inviter = event.params.inviter
  entity.designerId = event.params.designerId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleDesignerURI(event: DesignerURIEvent): void {
  let entity = new DesignerURI(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.designerId = event.params.designerId
  entity.uri = event.params.uri

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleReactionPacksUpdated(
  event: ReactionPacksUpdatedEvent,
): void {
  let entity = new ReactionPacksUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.packs = event.params.packs

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
