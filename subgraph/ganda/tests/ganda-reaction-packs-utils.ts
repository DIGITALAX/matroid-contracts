import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  Approval,
  ApprovalForAll,
  PackPurchased,
  ProjectRegistered,
  ReactionAdded,
  ReactionPackCreated,
  Transfer
} from "../generated/GandaReactionPacks/GandaReactionPacks"

export function createApprovalEvent(
  owner: Address,
  approved: Address,
  tokenId: BigInt
): Approval {
  let approvalEvent = changetype<Approval>(newMockEvent())

  approvalEvent.parameters = new Array()

  approvalEvent.parameters.push(
    new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner))
  )
  approvalEvent.parameters.push(
    new ethereum.EventParam("approved", ethereum.Value.fromAddress(approved))
  )
  approvalEvent.parameters.push(
    new ethereum.EventParam(
      "tokenId",
      ethereum.Value.fromUnsignedBigInt(tokenId)
    )
  )

  return approvalEvent
}

export function createApprovalForAllEvent(
  owner: Address,
  operator: Address,
  approved: boolean
): ApprovalForAll {
  let approvalForAllEvent = changetype<ApprovalForAll>(newMockEvent())

  approvalForAllEvent.parameters = new Array()

  approvalForAllEvent.parameters.push(
    new ethereum.EventParam("owner", ethereum.Value.fromAddress(owner))
  )
  approvalForAllEvent.parameters.push(
    new ethereum.EventParam("operator", ethereum.Value.fromAddress(operator))
  )
  approvalForAllEvent.parameters.push(
    new ethereum.EventParam("approved", ethereum.Value.fromBoolean(approved))
  )

  return approvalForAllEvent
}

export function createPackPurchasedEvent(
  buyer: Address,
  purchaseId: BigInt,
  packId: BigInt,
  price: BigInt,
  editionNumber: BigInt
): PackPurchased {
  let packPurchasedEvent = changetype<PackPurchased>(newMockEvent())

  packPurchasedEvent.parameters = new Array()

  packPurchasedEvent.parameters.push(
    new ethereum.EventParam("buyer", ethereum.Value.fromAddress(buyer))
  )
  packPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "purchaseId",
      ethereum.Value.fromUnsignedBigInt(purchaseId)
    )
  )
  packPurchasedEvent.parameters.push(
    new ethereum.EventParam("packId", ethereum.Value.fromUnsignedBigInt(packId))
  )
  packPurchasedEvent.parameters.push(
    new ethereum.EventParam("price", ethereum.Value.fromUnsignedBigInt(price))
  )
  packPurchasedEvent.parameters.push(
    new ethereum.EventParam(
      "editionNumber",
      ethereum.Value.fromUnsignedBigInt(editionNumber)
    )
  )

  return packPurchasedEvent
}

export function createProjectRegisteredEvent(
  metadata: Bytes
): ProjectRegistered {
  let projectRegisteredEvent = changetype<ProjectRegistered>(newMockEvent())

  projectRegisteredEvent.parameters = new Array()

  projectRegisteredEvent.parameters.push(
    new ethereum.EventParam("metadata", ethereum.Value.fromFixedBytes(metadata))
  )

  return projectRegisteredEvent
}

export function createReactionAddedEvent(
  packId: BigInt,
  reactionId: BigInt,
  reactionUri: string
): ReactionAdded {
  let reactionAddedEvent = changetype<ReactionAdded>(newMockEvent())

  reactionAddedEvent.parameters = new Array()

  reactionAddedEvent.parameters.push(
    new ethereum.EventParam("packId", ethereum.Value.fromUnsignedBigInt(packId))
  )
  reactionAddedEvent.parameters.push(
    new ethereum.EventParam(
      "reactionId",
      ethereum.Value.fromUnsignedBigInt(reactionId)
    )
  )
  reactionAddedEvent.parameters.push(
    new ethereum.EventParam(
      "reactionUri",
      ethereum.Value.fromString(reactionUri)
    )
  )

  return reactionAddedEvent
}

export function createReactionPackCreatedEvent(
  designer: Address,
  packId: BigInt,
  basePrice: BigInt,
  maxEditions: BigInt,
  holderReservedSpots: BigInt
): ReactionPackCreated {
  let reactionPackCreatedEvent = changetype<ReactionPackCreated>(newMockEvent())

  reactionPackCreatedEvent.parameters = new Array()

  reactionPackCreatedEvent.parameters.push(
    new ethereum.EventParam("designer", ethereum.Value.fromAddress(designer))
  )
  reactionPackCreatedEvent.parameters.push(
    new ethereum.EventParam("packId", ethereum.Value.fromUnsignedBigInt(packId))
  )
  reactionPackCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "basePrice",
      ethereum.Value.fromUnsignedBigInt(basePrice)
    )
  )
  reactionPackCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "maxEditions",
      ethereum.Value.fromUnsignedBigInt(maxEditions)
    )
  )
  reactionPackCreatedEvent.parameters.push(
    new ethereum.EventParam(
      "holderReservedSpots",
      ethereum.Value.fromUnsignedBigInt(holderReservedSpots)
    )
  )

  return reactionPackCreatedEvent
}

export function createTransferEvent(
  from: Address,
  to: Address,
  tokenId: BigInt
): Transfer {
  let transferEvent = changetype<Transfer>(newMockEvent())

  transferEvent.parameters = new Array()

  transferEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  transferEvent.parameters.push(
    new ethereum.EventParam("to", ethereum.Value.fromAddress(to))
  )
  transferEvent.parameters.push(
    new ethereum.EventParam(
      "tokenId",
      ethereum.Value.fromUnsignedBigInt(tokenId)
    )
  )

  return transferEvent
}
