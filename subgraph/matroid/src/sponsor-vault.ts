import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Deposited as DepositedEvent,
  RewardAdded as RewardAddedEvent,
  Claimed as ClaimedEvent,
} from "../generated/SponsorVault/SponsorVault";
import { SponsorVault, Sponsor } from "../generated/schema";

function loadVault(addr: Bytes): SponsorVault {
  let v = SponsorVault.load(addr);
  if (v == null) {
    v = new SponsorVault(addr);
    v.totalPoints = BigInt.fromI32(0);
    v.accRewardPerPoint = BigInt.fromI32(0);
    v.totalDeposited = BigInt.fromI32(0);
    v.totalRewards = BigInt.fromI32(0);
    v.totalClaimed = BigInt.fromI32(0);
    v.sponsorCount = 0;
  }
  return v;
}

export function handleDeposited(event: DepositedEvent): void {
  let vault = loadVault(event.address);
  let sponsor = Sponsor.load(event.params.sponsor);
  if (sponsor == null) {
    sponsor = new Sponsor(event.params.sponsor);
    sponsor.vault = event.address;
    sponsor.account = event.params.sponsor;
    sponsor.points = BigInt.fromI32(0);
    sponsor.totalDeposited = BigInt.fromI32(0);
    sponsor.totalClaimed = BigInt.fromI32(0);
    sponsor.firstSeenTimestamp = event.block.timestamp;
    sponsor.blockNumber = event.block.number;
    sponsor.blockTimestamp = event.block.timestamp;
    sponsor.transactionHash = event.transaction.hash;
    vault.sponsorCount = vault.sponsorCount + 1;
  }
  sponsor.points = sponsor.points.plus(event.params.amount);
  sponsor.totalDeposited = sponsor.totalDeposited.plus(event.params.amount);
  sponsor.save();

  vault.totalDeposited = vault.totalDeposited.plus(event.params.amount);
  vault.totalPoints = event.params.totalPoints;
  vault.save();
}

export function handleRewardAdded(event: RewardAddedEvent): void {
  let vault = loadVault(event.address);
  vault.accRewardPerPoint = event.params.accRewardPerPoint;
  vault.totalRewards = vault.totalRewards.plus(event.params.amount);
  vault.save();
}

export function handleClaimed(event: ClaimedEvent): void {
  let vault = loadVault(event.address);
  vault.totalClaimed = vault.totalClaimed.plus(event.params.amount);
  vault.save();

  let sponsor = Sponsor.load(event.params.sponsor);
  if (sponsor != null) {
    sponsor.totalClaimed = sponsor.totalClaimed.plus(event.params.amount);
    sponsor.save();
  }
}
