import { newMockEvent } from "matchstick-as"
import { ethereum, BigInt, Address } from "@graphprotocol/graph-ts"
import {
  GandaDeactivated,
  GandaRegistered,
  GandaUpdated,
  ReactionSubmitted
} from "../generated/GandaRegistry/GandaRegistry"

export function createGandaDeactivatedEvent(
  ganadaId: BigInt
): GandaDeactivated {
  let gandaDeactivatedEvent = changetype<GandaDeactivated>(newMockEvent())

  gandaDeactivatedEvent.parameters = new Array()

  gandaDeactivatedEvent.parameters.push(
    new ethereum.EventParam(
      "ganadaId",
      ethereum.Value.fromUnsignedBigInt(ganadaId)
    )
  )

  return gandaDeactivatedEvent
}

export function createGandaRegisteredEvent(
  ganadaId: BigInt,
  creator: Address,
  uri: string
): GandaRegistered {
  let gandaRegisteredEvent = changetype<GandaRegistered>(newMockEvent())

  gandaRegisteredEvent.parameters = new Array()

  gandaRegisteredEvent.parameters.push(
    new ethereum.EventParam(
      "ganadaId",
      ethereum.Value.fromUnsignedBigInt(ganadaId)
    )
  )
  gandaRegisteredEvent.parameters.push(
    new ethereum.EventParam("creator", ethereum.Value.fromAddress(creator))
  )
  gandaRegisteredEvent.parameters.push(
    new ethereum.EventParam("uri", ethereum.Value.fromString(uri))
  )

  return gandaRegisteredEvent
}

export function createGandaUpdatedEvent(
  ganadaId: BigInt,
  uri: string
): GandaUpdated {
  let gandaUpdatedEvent = changetype<GandaUpdated>(newMockEvent())

  gandaUpdatedEvent.parameters = new Array()

  gandaUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "ganadaId",
      ethereum.Value.fromUnsignedBigInt(ganadaId)
    )
  )
  gandaUpdatedEvent.parameters.push(
    new ethereum.EventParam("uri", ethereum.Value.fromString(uri))
  )

  return gandaUpdatedEvent
}

export function createReactionSubmittedEvent(
  ganadaId: BigInt,
  reactionId: BigInt,
  reviewer: Address
): ReactionSubmitted {
  let reactionSubmittedEvent = changetype<ReactionSubmitted>(newMockEvent())

  reactionSubmittedEvent.parameters = new Array()

  reactionSubmittedEvent.parameters.push(
    new ethereum.EventParam(
      "ganadaId",
      ethereum.Value.fromUnsignedBigInt(ganadaId)
    )
  )
  reactionSubmittedEvent.parameters.push(
    new ethereum.EventParam(
      "reactionId",
      ethereum.Value.fromUnsignedBigInt(reactionId)
    )
  )
  reactionSubmittedEvent.parameters.push(
    new ethereum.EventParam("reviewer", ethereum.Value.fromAddress(reviewer))
  )

  return reactionSubmittedEvent
}
