import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Claimed as ClaimedEvent,
  RewardNotified as RewardNotifiedEvent,
  Staked as StakedEvent,
  Unstaked as UnstakedEvent,
} from "../generated/GlobalStakingPool/GlobalStakingPool"
import {
  Global,
  GlobalClaimed,
  GlobalRewardNotified,
  Staked,
  Staker,
  Unstaked,
} from "../generated/schema"

const GLOBAL_ID = Bytes.fromUTF8("global");

function getOrCreateStaker(user: Bytes): Staker {
  let stakerId = GLOBAL_ID.concat(user);
  let staker = Staker.load(stakerId);
  if (!staker) {
    staker = new Staker(stakerId);
    staker.pool = GLOBAL_ID;
    staker.user = user;
    staker.stakedAmount = BigInt.fromI32(0);
    staker.staked = [];
    staker.unstaked = [];
  }
  return staker;
}

export function handleClaimed(event: ClaimedEvent): void {
  let entity = new GlobalClaimed(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.user = event.params.user
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleRewardNotified(event: RewardNotifiedEvent): void {
  let entity = new GlobalRewardNotified(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  let global = Global.load(GLOBAL_ID);
  if (global) {
    let total = global.rewardNotifiedTotal;
    if (!total) {
      total = BigInt.fromI32(0);
    }
    global.rewardNotifiedTotal = total.plus(event.params.amount);
    global.save();
  }
}

export function handleStaked(event: StakedEvent): void {
  let entity = new Staked(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.user = event.params.user
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  let staker = getOrCreateStaker(event.params.user);
  let previous = staker.stakedAmount;
  staker.stakedAmount = previous.plus(event.params.amount);
  let history = staker.staked;
  if (!history) {
    history = [];
  }
  history.push(entity.id);
  staker.staked = history;
  staker.save();

  let global = Global.load(GLOBAL_ID);
  if (global) {
    let total = global.totalStaked;
    if (!total) {
      total = BigInt.fromI32(0);
    }
    global.totalStaked = total.plus(event.params.amount);
    if (previous.equals(BigInt.fromI32(0))) {
      let count = global.stakerCount;
      if (!count) {
        count = 0;
      }
      global.stakerCount = count + 1;
      let stakers = global.stakers;
      if (!stakers) {
        stakers = [];
      }
      let exists = false;
      for (let i = 0; i < stakers.length; i++) {
        if (stakers[i].equals(staker.id)) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        stakers.push(staker.id);
      }
      global.stakers = stakers;
    }
    global.save();
  }
}

export function handleUnstaked(event: UnstakedEvent): void {
  let entity = new Unstaked(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.user = event.params.user
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  let staker = getOrCreateStaker(event.params.user);
  let previous = staker.stakedAmount;
  let nextAmount = previous.minus(event.params.amount);
  staker.stakedAmount = nextAmount;
  let history = staker.unstaked;
  if (!history) {
    history = [];
  }
  history.push(entity.id);
  staker.unstaked = history;
  staker.save();

  let global = Global.load(GLOBAL_ID);
  if (global) {
    let total = global.totalStaked;
    if (!total) {
      total = BigInt.fromI32(0);
    }
    global.totalStaked = total.minus(event.params.amount);
    if (previous.gt(BigInt.fromI32(0)) && nextAmount.equals(BigInt.fromI32(0))) {
      let count = global.stakerCount;
      if (!count) {
        count = 0;
      }
      global.stakerCount = count > 0 ? count - 1 : 0;
    }
    global.save();
  }
}
