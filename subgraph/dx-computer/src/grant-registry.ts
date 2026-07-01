import { BigInt, Bytes, store } from "@graphprotocol/graph-ts";
import {
  GrantCreated as GrantCreatedEvent,
  GrantFunded as GrantFundedEvent,
  GrantRemoved as GrantRemovedEvent,
  Claimed as ClaimedEvent,
} from "../generated/GrantRegistry/GrantRegistry";
import { Grant, GrantFunder, Treeliner } from "../generated/schema";

function loadTreeliner(addr: Bytes): Treeliner {
  let id = addr.toHexString();
  let t = Treeliner.load(id);
  if (t == null) {
    t = new Treeliner(id);
    t.address = addr;
    t.totalStaked = BigInt.fromI32(0);
    t.totalClaimed = BigInt.fromI32(0);
    t.grantsFunded = 0;
  }
  return t;
}

function isCleanUri(uri: string): boolean {
  return (
    uri.startsWith("ipfs://") ||
    uri.startsWith("https://") ||
    uri.startsWith("ar://")
  );
}

export function handleGrantCreated(event: GrantCreatedEvent): void {
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  let grant = new Grant(event.params.grantId.toString());
  grant.grantId = event.params.grantId;
  grant.kitId = event.params.kitId;
  grant.kit = event.params.kitId.toString();
  grant.creator = event.params.creator;
  grant.purposeHash = event.params.purposeHash;
  grant.contentUri = event.params.contentUri;
  grant.budget = event.params.budget;
  grant.raised = BigInt.fromI32(0);
  grant.totalShares = BigInt.fromI32(0);
  grant.salesShareBps = event.params.salesShareBps;
  grant.funders = 0;
  grant.createdAtBlock = event.block.number;
  grant.createdAtTimestamp = event.block.timestamp;
  grant.transactionHash = event.transaction.hash;
  grant.save();
}

export function handleGrantRemoved(event: GrantRemovedEvent): void {
  store.remove("Grant", event.params.grantId.toString());
}

export function handleGrantFunded(event: GrantFundedEvent): void {
  let grant = Grant.load(event.params.grantId.toString());
  if (grant == null) {
    return;
  }
  grant.raised = grant.raised.plus(event.params.amount);
  grant.totalShares = grant.totalShares.plus(event.params.amount);

  let funderId =
    event.params.grantId.toString() + "-" + event.params.funder.toHexString();
  let funder = GrantFunder.load(funderId);
  let treeliner = loadTreeliner(event.params.funder);
  if (funder == null) {
    funder = new GrantFunder(funderId);
    funder.grant = grant.id;
    funder.funder = event.params.funder;
    funder.shares = BigInt.fromI32(0);
    grant.funders = grant.funders + 1;
    treeliner.grantsFunded = treeliner.grantsFunded + 1;
  }
  funder.shares = event.params.totalFunderShares;
  funder.save();

  treeliner.totalStaked = treeliner.totalStaked.plus(event.params.amount);
  treeliner.save();

  grant.save();
}

export function handleClaimed(event: ClaimedEvent): void {
  let treeliner = loadTreeliner(event.params.funder);
  treeliner.totalClaimed = treeliner.totalClaimed.plus(event.params.amount);
  treeliner.save();
}
