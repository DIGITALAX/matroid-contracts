import { newMockEvent } from "matchstick-as"
import { ethereum, BigInt, Address } from "@graphprotocol/graph-ts"
import {
  ClaimableCleared,
  ClaimableSet,
  Claimed,
  DistributionStarted,
  EpochFinalized,
  FundsDeposited,
  ProjectSlashed,
  SlashResolved,
  SlashRewardNotified,
  SlashingContractUpdated,
  TargetDurationUpdated,
  TargetReconciled,
  TargetUpdated
} from "../generated/Treasury/Treasury"

export function createClaimableClearedEvent(
  epoch: BigInt,
  project: Address
): ClaimableCleared {
  let claimableClearedEvent = changetype<ClaimableCleared>(newMockEvent())

  claimableClearedEvent.parameters = new Array()

  claimableClearedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  claimableClearedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )

  return claimableClearedEvent
}

export function createClaimableSetEvent(
  epoch: BigInt,
  project: Address,
  amount: BigInt
): ClaimableSet {
  let claimableSetEvent = changetype<ClaimableSet>(newMockEvent())

  claimableSetEvent.parameters = new Array()

  claimableSetEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  claimableSetEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  claimableSetEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return claimableSetEvent
}

export function createClaimedEvent(
  epoch: BigInt,
  project: Address,
  claimer: Address,
  amount: BigInt
): Claimed {
  let claimedEvent = changetype<Claimed>(newMockEvent())

  claimedEvent.parameters = new Array()

  claimedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam("claimer", ethereum.Value.fromAddress(claimer))
  )
  claimedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return claimedEvent
}

export function createDistributionStartedEvent(
  timestamp: BigInt
): DistributionStarted {
  let distributionStartedEvent = changetype<DistributionStarted>(newMockEvent())

  distributionStartedEvent.parameters = new Array()

  distributionStartedEvent.parameters.push(
    new ethereum.EventParam(
      "timestamp",
      ethereum.Value.fromUnsignedBigInt(timestamp)
    )
  )

  return distributionStartedEvent
}

export function createEpochFinalizedEvent(
  epoch: BigInt,
  totalScore: BigInt,
  activeProjects: BigInt,
  budget: BigInt
): EpochFinalized {
  let epochFinalizedEvent = changetype<EpochFinalized>(newMockEvent())

  epochFinalizedEvent.parameters = new Array()

  epochFinalizedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  epochFinalizedEvent.parameters.push(
    new ethereum.EventParam(
      "totalScore",
      ethereum.Value.fromUnsignedBigInt(totalScore)
    )
  )
  epochFinalizedEvent.parameters.push(
    new ethereum.EventParam(
      "activeProjects",
      ethereum.Value.fromUnsignedBigInt(activeProjects)
    )
  )
  epochFinalizedEvent.parameters.push(
    new ethereum.EventParam("budget", ethereum.Value.fromUnsignedBigInt(budget))
  )

  return epochFinalizedEvent
}

export function createFundsDepositedEvent(
  from: Address,
  amount: BigInt
): FundsDeposited {
  let fundsDepositedEvent = changetype<FundsDeposited>(newMockEvent())

  fundsDepositedEvent.parameters = new Array()

  fundsDepositedEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  fundsDepositedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return fundsDepositedEvent
}

export function createProjectSlashedEvent(
  epoch: BigInt,
  project: Address,
  slashBps: i32,
  blacklisted: boolean
): ProjectSlashed {
  let projectSlashedEvent = changetype<ProjectSlashed>(newMockEvent())

  projectSlashedEvent.parameters = new Array()

  projectSlashedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  projectSlashedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  projectSlashedEvent.parameters.push(
    new ethereum.EventParam(
      "slashBps",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(slashBps))
    )
  )
  projectSlashedEvent.parameters.push(
    new ethereum.EventParam(
      "blacklisted",
      ethereum.Value.fromBoolean(blacklisted)
    )
  )

  return projectSlashedEvent
}

export function createSlashResolvedEvent(
  epoch: BigInt,
  project: Address,
  voterReward: BigInt
): SlashResolved {
  let slashResolvedEvent = changetype<SlashResolved>(newMockEvent())

  slashResolvedEvent.parameters = new Array()

  slashResolvedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  slashResolvedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  slashResolvedEvent.parameters.push(
    new ethereum.EventParam(
      "voterReward",
      ethereum.Value.fromUnsignedBigInt(voterReward)
    )
  )

  return slashResolvedEvent
}

export function createSlashRewardNotifiedEvent(
  epoch: BigInt,
  project: Address,
  amount: BigInt
): SlashRewardNotified {
  let slashRewardNotifiedEvent = changetype<SlashRewardNotified>(newMockEvent())

  slashRewardNotifiedEvent.parameters = new Array()

  slashRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("epoch", ethereum.Value.fromUnsignedBigInt(epoch))
  )
  slashRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  slashRewardNotifiedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return slashRewardNotifiedEvent
}

export function createSlashingContractUpdatedEvent(
  oldContract: Address,
  newContract: Address
): SlashingContractUpdated {
  let slashingContractUpdatedEvent =
    changetype<SlashingContractUpdated>(newMockEvent())

  slashingContractUpdatedEvent.parameters = new Array()

  slashingContractUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldContract",
      ethereum.Value.fromAddress(oldContract)
    )
  )
  slashingContractUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newContract",
      ethereum.Value.fromAddress(newContract)
    )
  )

  return slashingContractUpdatedEvent
}

export function createTargetDurationUpdatedEvent(
  oldDuration: BigInt,
  newDuration: BigInt
): TargetDurationUpdated {
  let targetDurationUpdatedEvent =
    changetype<TargetDurationUpdated>(newMockEvent())

  targetDurationUpdatedEvent.parameters = new Array()

  targetDurationUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldDuration",
      ethereum.Value.fromUnsignedBigInt(oldDuration)
    )
  )
  targetDurationUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newDuration",
      ethereum.Value.fromUnsignedBigInt(newDuration)
    )
  )

  return targetDurationUpdatedEvent
}

export function createTargetReconciledEvent(
  oldTarget: BigInt,
  newTarget: BigInt
): TargetReconciled {
  let targetReconciledEvent = changetype<TargetReconciled>(newMockEvent())

  targetReconciledEvent.parameters = new Array()

  targetReconciledEvent.parameters.push(
    new ethereum.EventParam(
      "oldTarget",
      ethereum.Value.fromUnsignedBigInt(oldTarget)
    )
  )
  targetReconciledEvent.parameters.push(
    new ethereum.EventParam(
      "newTarget",
      ethereum.Value.fromUnsignedBigInt(newTarget)
    )
  )

  return targetReconciledEvent
}

export function createTargetUpdatedEvent(
  oldTarget: BigInt,
  newTarget: BigInt
): TargetUpdated {
  let targetUpdatedEvent = changetype<TargetUpdated>(newMockEvent())

  targetUpdatedEvent.parameters = new Array()

  targetUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "oldTarget",
      ethereum.Value.fromUnsignedBigInt(oldTarget)
    )
  )
  targetUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "newTarget",
      ethereum.Value.fromUnsignedBigInt(newTarget)
    )
  )

  return targetUpdatedEvent
}
