import { Bytes } from "@graphprotocol/graph-ts";
import {
  Deposited as DepositedEvent,
  Withdrawn as WithdrawnEvent,
} from "../generated/BalancePool/BalancePool";
import { PoolEvent } from "../generated/schema";

export function handleDeposited(event: DepositedEvent): void {
  let entry = new PoolEvent(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  );
  entry.bucket = event.params.bucket;
  entry.kind = "deposit";
  entry.commitment = event.params.commitment;
  entry.leafIndex = event.params.leafIndex.toI32();
  entry.root = event.params.root;
  entry.blockNumber = event.block.number;
  entry.logIndex = event.logIndex;
  entry.blockTimestamp = event.block.timestamp;
  entry.transactionHash = event.transaction.hash;
  entry.save();
}

export function handleWithdrawn(event: WithdrawnEvent): void {
  let entry = new PoolEvent(
    event.transaction.hash.toHex() + "-" + event.logIndex.toString()
  );
  entry.bucket = event.params.bucket;
  entry.kind = "withdraw";
  entry.commitment = Bytes.fromHexString(
    "0x0000000000000000000000000000000000000000000000000000000000000000"
  );
  entry.leafIndex = event.params.leafIndex.toI32();
  entry.root = event.params.root;
  entry.blockNumber = event.block.number;
  entry.logIndex = event.logIndex;
  entry.blockTimestamp = event.block.timestamp;
  entry.transactionHash = event.transaction.hash;
  entry.save();
}
