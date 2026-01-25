import { newMockEvent } from "matchstick-as"
import { ethereum, BigInt, Address } from "@graphprotocol/graph-ts"
import {
  DesignerDeactivated,
  DesignerInvited,
  DesignerURI,
  ReactionPacksUpdated
} from "../generated/GandaDesigners/GandaDesigners"

export function createDesignerDeactivatedEvent(
  designerId: BigInt,
  inviter: Address
): DesignerDeactivated {
  let designerDeactivatedEvent = changetype<DesignerDeactivated>(newMockEvent())

  designerDeactivatedEvent.parameters = new Array()

  designerDeactivatedEvent.parameters.push(
    new ethereum.EventParam(
      "designerId",
      ethereum.Value.fromUnsignedBigInt(designerId)
    )
  )
  designerDeactivatedEvent.parameters.push(
    new ethereum.EventParam("inviter", ethereum.Value.fromAddress(inviter))
  )

  return designerDeactivatedEvent
}

export function createDesignerInvitedEvent(
  designer: Address,
  inviter: Address,
  designerId: BigInt
): DesignerInvited {
  let designerInvitedEvent = changetype<DesignerInvited>(newMockEvent())

  designerInvitedEvent.parameters = new Array()

  designerInvitedEvent.parameters.push(
    new ethereum.EventParam("designer", ethereum.Value.fromAddress(designer))
  )
  designerInvitedEvent.parameters.push(
    new ethereum.EventParam("inviter", ethereum.Value.fromAddress(inviter))
  )
  designerInvitedEvent.parameters.push(
    new ethereum.EventParam(
      "designerId",
      ethereum.Value.fromUnsignedBigInt(designerId)
    )
  )

  return designerInvitedEvent
}

export function createDesignerURIEvent(
  designerId: BigInt,
  uri: string
): DesignerURI {
  let designerUriEvent = changetype<DesignerURI>(newMockEvent())

  designerUriEvent.parameters = new Array()

  designerUriEvent.parameters.push(
    new ethereum.EventParam(
      "designerId",
      ethereum.Value.fromUnsignedBigInt(designerId)
    )
  )
  designerUriEvent.parameters.push(
    new ethereum.EventParam("uri", ethereum.Value.fromString(uri))
  )

  return designerUriEvent
}

export function createReactionPacksUpdatedEvent(
  packs: Address
): ReactionPacksUpdated {
  let reactionPacksUpdatedEvent =
    changetype<ReactionPacksUpdated>(newMockEvent())

  reactionPacksUpdatedEvent.parameters = new Array()

  reactionPacksUpdatedEvent.parameters.push(
    new ethereum.EventParam("packs", ethereum.Value.fromAddress(packs))
  )

  return reactionPacksUpdatedEvent
}
