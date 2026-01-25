import {
  MatroidIn as MatroidInEvent,
  MatroidOut as MatroidOutEvent,
  ProjectRegistered as ProjectRegisteredEvent,
} from "../generated/MatroidKit/MatroidKit"
import {
  MatroidIn,
  MatroidOut,
  MatroidKitProjectRegistered,
  Global,
} from "../generated/schema"
import { Bytes } from "@graphprotocol/graph-ts"

const GLOBAL_ID = Bytes.fromUTF8("global")

export function handleMatroidIn(event: MatroidInEvent): void {
  let entity = new MatroidIn(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.project = event.params.project
  entity.user = event.params.user
  entity.token = event.params.token
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  let global = Global.load(GLOBAL_ID)
  if (global) {
    let ins = global.in_
    if (!ins) {
      ins = new Array<Bytes>()
    }
    ins.push(entity.id)
    global.in_ = ins
    global.save()
  }
}

export function handleMatroidOut(event: MatroidOutEvent): void {
  let entity = new MatroidOut(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.project = event.params.project
  entity.user = event.params.user
  entity.token = event.params.token
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  let global = Global.load(GLOBAL_ID)
  if (global) {
    let outs = global.out
    if (!outs) {
      outs = new Array<Bytes>()
    }
    outs.push(entity.id)
    global.out = outs
    global.save()
  }
}

export function handleProjectRegistered(event: ProjectRegisteredEvent): void {
  let entity = new MatroidKitProjectRegistered(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.project = event.params.project
  entity.metadata = event.params.metadata

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
