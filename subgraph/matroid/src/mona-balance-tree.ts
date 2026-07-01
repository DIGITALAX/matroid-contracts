import { Registered as RegisteredEvent } from "../generated/MonaBalanceTree/MonaBalanceTree";
import { BalanceLeaf } from "../generated/schema";

export function handleRegistered(event: RegisteredEvent): void {
  let leaf = new BalanceLeaf(event.params.leafIndex.toString());
  leaf.holder = event.params.holder;
  leaf.balance = event.params.balance;
  leaf.leafIndex = event.params.leafIndex.toI32();
  leaf.root = event.params.root;
  leaf.blockNumber = event.block.number;
  leaf.blockTimestamp = event.block.timestamp;
  leaf.transactionHash = event.transaction.hash;
  leaf.save();
}
