import { newMockEvent } from "matchstick-as"
import { ethereum, Address } from "@graphprotocol/graph-ts"
import {
  ProjectPoolCreated,
  ProjectPoolsCreated
} from "../generated/StakingFactory/StakingFactory"

export function createProjectPoolCreatedEvent(
  project: Address,
  pool: Address
): ProjectPoolCreated {
  let projectPoolCreatedEvent = changetype<ProjectPoolCreated>(newMockEvent())

  projectPoolCreatedEvent.parameters = new Array()

  projectPoolCreatedEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  projectPoolCreatedEvent.parameters.push(
    new ethereum.EventParam("pool", ethereum.Value.fromAddress(pool))
  )

  return projectPoolCreatedEvent
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
