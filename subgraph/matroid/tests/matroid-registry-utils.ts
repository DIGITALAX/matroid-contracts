import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  ClaimerUpdated,
  FlowRecorded,
  MatroidKitUpdated,
  ProjectPoolsCreated,
  ProjectRegistered,
  RewardSplitsUpdated
} from "../generated/MatroidRegistry/MatroidRegistry"

export function createClaimerUpdatedEvent(
  project: Address,
  claimer: Address,
  allowed: boolean
): ClaimerUpdated {
  let claimerUpdatedEvent = changetype<ClaimerUpdated>(newMockEvent())

  claimerUpdatedEvent.parameters = new Array()

  claimerUpdatedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  claimerUpdatedEvent.parameters.push(
    new ethereum.EventParam("claimer", ethereum.Value.fromAddress(claimer))
  )
  claimerUpdatedEvent.parameters.push(
    new ethereum.EventParam("allowed", ethereum.Value.fromBoolean(allowed))
  )

  return claimerUpdatedEvent
}

export function createFlowRecordedEvent(
  project: Address,
  user: Address,
  token: Address,
  amount: BigInt,
  isIn: boolean
): FlowRecorded {
  let flowRecordedEvent = changetype<FlowRecorded>(newMockEvent())

  flowRecordedEvent.parameters = new Array()

  flowRecordedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  flowRecordedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  flowRecordedEvent.parameters.push(
    new ethereum.EventParam("token", ethereum.Value.fromAddress(token))
  )
  flowRecordedEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )
  flowRecordedEvent.parameters.push(
    new ethereum.EventParam("isIn", ethereum.Value.fromBoolean(isIn))
  )

  return flowRecordedEvent
}

export function createMatroidKitUpdatedEvent(
  oldKit: Address,
  newKit: Address
): MatroidKitUpdated {
  let matroidKitUpdatedEvent = changetype<MatroidKitUpdated>(newMockEvent())

  matroidKitUpdatedEvent.parameters = new Array()

  matroidKitUpdatedEvent.parameters.push(
    new ethereum.EventParam("oldKit", ethereum.Value.fromAddress(oldKit))
  )
  matroidKitUpdatedEvent.parameters.push(
    new ethereum.EventParam("newKit", ethereum.Value.fromAddress(newKit))
  )

  return matroidKitUpdatedEvent
}

export function createProjectPoolsCreatedEvent(
  project: Address,
  erc20Pool: Address,
  nftPool: Address
): ProjectPoolsCreated {
  let projectPoolsCreatedEvent = changetype<ProjectPoolsCreated>(newMockEvent())

  projectPoolsCreatedEvent.parameters = new Array()

  projectPoolsCreatedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  projectPoolsCreatedEvent.parameters.push(
    new ethereum.EventParam("erc20Pool", ethereum.Value.fromAddress(erc20Pool))
  )
  projectPoolsCreatedEvent.parameters.push(
    new ethereum.EventParam("nftPool", ethereum.Value.fromAddress(nftPool))
  )

  return projectPoolsCreatedEvent
}

export function createProjectRegisteredEvent(
  project: Address,
  metadata: Bytes
): ProjectRegistered {
  let projectRegisteredEvent = changetype<ProjectRegistered>(newMockEvent())

  projectRegisteredEvent.parameters = new Array()

  projectRegisteredEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  projectRegisteredEvent.parameters.push(
    new ethereum.EventParam("metadata", ethereum.Value.fromFixedBytes(metadata))
  )

  return projectRegisteredEvent
}

export function createRewardSplitsUpdatedEvent(
  project: Address,
  globalSplitBps: i32,
  projectErc20SplitBps: i32,
  projectNftSplitBps: i32
): RewardSplitsUpdated {
  let rewardSplitsUpdatedEvent = changetype<RewardSplitsUpdated>(newMockEvent())

  rewardSplitsUpdatedEvent.parameters = new Array()

  rewardSplitsUpdatedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  rewardSplitsUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "globalSplitBps",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(globalSplitBps))
    )
  )
  rewardSplitsUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "projectErc20SplitBps",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(projectErc20SplitBps))
    )
  )
  rewardSplitsUpdatedEvent.parameters.push(
    new ethereum.EventParam(
      "projectNftSplitBps",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(projectNftSplitBps))
    )
  )

  return rewardSplitsUpdatedEvent
}
