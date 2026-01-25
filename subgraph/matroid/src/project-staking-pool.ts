import { Address, BigInt, Bytes, dataSource } from "@graphprotocol/graph-ts";
import {
  Claimed as ClaimedEvent,
  ProjectStakingPool as ProjectStakingPoolContract,
  RewardTokenAdded as RewardTokenAddedEvent,
  RewardTokenRemoved as RewardTokenRemovedEvent,
  RewardNotified as RewardNotifiedEvent,
  Staked as StakedEvent,
  Unstaked as UnstakedEvent,
} from "../generated/templates/ProjectStakingPool/ProjectStakingPool";
import { ProjectPoolERC20, ERC20Staker, PoolClaim } from "../generated/schema";

function getPoolAddress(): Address {
  return dataSource.address();
}

function getPoolId(): Bytes {
  return getPoolAddress();
}

function getOrCreatePool(): ProjectPoolERC20 {
  let poolId = getPoolId();
  let pool = ProjectPoolERC20.load(poolId);
  if (!pool) {
    pool = new ProjectPoolERC20(poolId);
    let contract = ProjectStakingPoolContract.bind(getPoolAddress());
    pool.project = contract.project();
    pool.totalStaked = BigInt.fromI32(0);
    pool.rewardNotifiedTotal = BigInt.fromI32(0);
    pool.claims = [];
    pool.stakerCount = 0;
    pool.stakers = [];
  }
  return pool;
}

function getOrCreateStaker(poolId: Bytes, user: Bytes): ERC20Staker {
  let stakerId = poolId.concat(user);
  let staker = ERC20Staker.load(stakerId);
  if (!staker) {
    staker = new ERC20Staker(stakerId);
    staker.pool = poolId;
    staker.user = user;
    staker.stakedAmount = BigInt.fromI32(0);
  }
  return staker;
}

export function handleRewardNotified(event: RewardNotifiedEvent): void {
  let pool = getOrCreatePool();
  pool.rewardNotifiedTotal = pool.rewardNotifiedTotal.plus(event.params.amount);
  pool.save();
}

export function handleRewardTokenAdded(_event: RewardTokenAddedEvent): void {
  let pool = getOrCreatePool();
  let tokens = pool.rewardTokens;
  if (!tokens) {
    tokens = new Array<Bytes>();
  }
  let exists = false;
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].equals(_event.params.token)) {
      exists = true;
      break;
    }
  }
  if (!exists) {
    tokens.push(_event.params.token);
  }
  pool.rewardTokens = tokens;
  pool.save();
}

export function handleRewardTokenRemoved(event: RewardTokenRemovedEvent): void {
  let pool = getOrCreatePool();
  let tokens = pool.rewardTokens;
  if (!tokens) {
    tokens = new Array<Bytes>();
  }
  let nextTokens = new Array<Bytes>();
  for (let i = 0; i < tokens.length; i++) {
    if (!tokens[i].equals(event.params.token)) {
      nextTokens.push(tokens[i]);
    }
  }
  pool.rewardTokens = nextTokens;
  pool.save();
}

export function handleStaked(event: StakedEvent): void {
  let pool = getOrCreatePool();
  let staker = getOrCreateStaker(pool.id, event.params.user);
  let previous = staker.stakedAmount;
  staker.stakedAmount = previous.plus(event.params.amount);
  staker.save();

  pool.totalStaked = pool.totalStaked.plus(event.params.amount);
  if (previous.equals(BigInt.fromI32(0))) {
    pool.stakerCount = pool.stakerCount + 1;
    let stakers = pool.stakers;
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
    pool.stakers = stakers;
  }
  pool.save();
}

export function handleUnstaked(event: UnstakedEvent): void {
  let pool = getOrCreatePool();
  let staker = getOrCreateStaker(pool.id, event.params.user);
  let previous = staker.stakedAmount;
  let nextAmount = previous.minus(event.params.amount);
  staker.stakedAmount = nextAmount;
  staker.save();

  pool.totalStaked = pool.totalStaked.minus(event.params.amount);
  if (previous.gt(BigInt.fromI32(0)) && nextAmount.equals(BigInt.fromI32(0))) {
    pool.stakerCount = pool.stakerCount > 0 ? pool.stakerCount - 1 : 0;
  }
  pool.save();
}

export function handleClaimed(_event: ClaimedEvent): void {
  let pool = getOrCreatePool();
  let claim = new PoolClaim(
    _event.transaction.hash.concatI32(_event.logIndex.toI32()),
  );
  claim.pool = pool.id;
  claim.user = _event.params.user;
  claim.token = _event.params.token;
  claim.amount = _event.params.amount;
  claim.blockNumber = _event.block.number;
  claim.blockTimestamp = _event.block.timestamp;
  claim.transactionHash = _event.transaction.hash;
  claim.save();

  let claims = pool.claims;
  if (!claims) {
    claims = [];
  }
  claims.push(claim.id);
  pool.claims = claims;
  pool.save();
}
