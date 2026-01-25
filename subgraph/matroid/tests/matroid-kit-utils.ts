import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  MatroidIn,
  MatroidOut,
  ProjectRegistered
} from "../generated/MatroidKit/MatroidKit"

export function createMatroidInEvent(
  project: Address,
  user: Address,
  token: Address,
  amount: BigInt
): MatroidIn {
  let matroidInEvent = changetype<MatroidIn>(newMockEvent())

  matroidInEvent.parameters = new Array()

  matroidInEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  matroidInEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  matroidInEvent.parameters.push(
    new ethereum.EventParam("token", ethereum.Value.fromAddress(token))
  )
  matroidInEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return matroidInEvent
}

export function createMatroidOutEvent(
  project: Address,
  user: Address,
  token: Address,
  amount: BigInt
): MatroidOut {
  let matroidOutEvent = changetype<MatroidOut>(newMockEvent())

  matroidOutEvent.parameters = new Array()

  matroidOutEvent.parameters.push(
    new ethereum.EventParam("project", ethereum.Value.fromAddress(project))
  )
  matroidOutEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  matroidOutEvent.parameters.push(
    new ethereum.EventParam("token", ethereum.Value.fromAddress(token))
  )
  matroidOutEvent.parameters.push(
    new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount))
  )

  return matroidOutEvent
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
