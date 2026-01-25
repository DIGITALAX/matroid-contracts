import {
  Approval as ApprovalEvent,
  ApprovalForAll as ApprovalForAllEvent,
  PackPurchased as PackPurchasedEvent,
  ProjectRegistered as ProjectRegisteredEvent,
  ReactionAdded as ReactionAddedEvent,
  ReactionPackCreated as ReactionPackCreatedEvent,
  Transfer as TransferEvent,
} from "../generated/GandaReactionPacks/GandaReactionPacks"
import {
  Approval,
  ApprovalForAll,
  PackPurchased,
  ProjectRegistered,
  ReactionAdded,
  ReactionPackCreated,
  Transfer,
} from "../generated/schema"

export function handleApproval(event: ApprovalEvent): void {
  let entity = new Approval(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.owner = event.params.owner
  entity.approved = event.params.approved
  entity.tokenId = event.params.tokenId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleApprovalForAll(event: ApprovalForAllEvent): void {
  let entity = new ApprovalForAll(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.owner = event.params.owner
  entity.operator = event.params.operator
  entity.approved = event.params.approved

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handlePackPurchased(event: PackPurchasedEvent): void {
  let entity = new PackPurchased(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.buyer = event.params.buyer
  entity.purchaseId = event.params.purchaseId
  entity.packId = event.params.packId
  entity.price = event.params.price
  entity.editionNumber = event.params.editionNumber

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleProjectRegistered(event: ProjectRegisteredEvent): void {
  let entity = new ProjectRegistered(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.metadata = event.params.metadata

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleReactionAdded(event: ReactionAddedEvent): void {
  let entity = new ReactionAdded(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.packId = event.params.packId
  entity.reactionId = event.params.reactionId
  entity.reactionUri = event.params.reactionUri

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleReactionPackCreated(
  event: ReactionPackCreatedEvent,
): void {
  let entity = new ReactionPackCreated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.designer = event.params.designer
  entity.packId = event.params.packId
  entity.basePrice = event.params.basePrice
  entity.maxEditions = event.params.maxEditions
  entity.holderReservedSpots = event.params.holderReservedSpots

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleTransfer(event: TransferEvent): void {
  let entity = new Transfer(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.from = event.params.from
  entity.to = event.params.to
  entity.tokenId = event.params.tokenId

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
