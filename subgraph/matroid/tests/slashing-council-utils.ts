import { newMockEvent } from "matchstick-as"
import { ethereum, BigInt, Address } from "@graphprotocol/graph-ts"
import {
  ProposalExecuted,
  ProposalResolved,
  Voted,
  VoterRewardNotified,
  VoterRewarded
} from "../generated/SlashingCouncil/SlashingCouncil"

export function createProposalExecutedEvent(
  epoch: BigInt,
  project: Address,
  slashBps: i32,
  blacklist: boolean
): ProposalExecuted {
  let proposalExecutedEvent = changetype<ProposalExecuted>(newMockEvent())

  proposalExecutedEvent.parameters = new Array()

  proposalExecutedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  proposalExecutedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  proposalExecutedEvent.parameters.push(
    new ethereum.EventParam(
      "slashBps",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(slashBps))
    )
  )
  proposalExecutedEvent.parameters.push(
    new ethereum.EventParam("blacklist", ethereum.Value.fromBoolean(blacklist))
  )

  return proposalExecutedEvent
}

export function createProposalResolvedEvent(
  epoch: BigInt,
  project: Address,
  passed: boolean
): ProposalResolved {
  let proposalResolvedEvent = changetype<ProposalResolved>(newMockEvent())

  proposalResolvedEvent.parameters = new Array()

  proposalResolvedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  proposalResolvedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  proposalResolvedEvent.parameters.push(
    new ethereum.EventParam("passed", ethereum.Value.fromBoolean(passed))
  )

  return proposalResolvedEvent
}

export function createVotedEvent(
  epoch: BigInt,
  project: Address,
  voter: Address,
  weight: BigInt
): Voted {
  let votedEvent = changetype<Voted>(newMockEvent())

  votedEvent.parameters = new Array()

  votedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  votedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  votedEvent.parameters.push(
    new ethereum.EventParam("voter", ethereum.Value.fromAddress(voter))
  )
  votedEvent.parameters.push(
    new ethereum.EventParam("weight", ethereum.Value.fromUnsignedBigInt(weight))
  )

  return votedEvent
}

export function createVoterRewardNotifiedEvent(
  epoch: BigInt,
  project: Address,
  amount: BigInt
): VoterRewardNotified {
  let voterRewardNotifiedEvent = changetype<VoterRewardNotified>(newMockEvent())

  voterRewardNotifiedEvent.parameters = new Array()

  voterRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  voterRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  voterRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return voterRewardNotifiedEvent
}

export function createVoterRewardedEvent(
  epoch: BigInt,
  project: Address,
  voter: Address,
  amount: BigInt
): VoterRewarded {
  let voterRewardedEvent = changetype<VoterRewarded>(newMockEvent())

  voterRewardedEvent.parameters = new Array()

  voterRewardedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  voterRewardedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  voterRewardedEvent.parameters.push(
    new ethereum.EventParam("voter", ethereum.Value.fromAddress(voter))
  )
  voterRewardedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return voterRewardedEvent
}
