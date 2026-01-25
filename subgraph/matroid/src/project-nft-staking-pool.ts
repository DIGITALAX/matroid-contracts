import { Address, BigInt, Bytes, dataSource } from "@graphprotocol/graph-ts";
import {
  Claimed as ClaimedEvent,
  NftStaked as NftStakedEvent,
  NftUnstaked as NftUnstakedEvent,
  NftWhitelisted as NftWhitelistedEvent,
  ProjectNFTStakingPool as ProjectNFTStakingPoolContract,
  RewardTokenAdded as RewardTokenAddedEvent,
  RewardTokenRemoved as RewardTokenRemovedEvent,
  NftWeightUpdated as NftWeightUpdatedEvent,
  RewardNotified as RewardNotifiedEvent,
} from "../generated/templates/ProjectNFTStakingPool/ProjectNFTStakingPool";
import {
  ProjectPoolNFT,
  NFTStaker,
  PoolClaim,
  WhitelistedNFT,
} from "../generated/schema";

function getPoolAddress(): Address {
  return dataSource.address();
}

function getPoolId(): Bytes {
  return getPoolAddress();
}

function getOrCreatePool(): ProjectPoolNFT {
  let poolId = getPoolId();
  let pool = ProjectPoolNFT.load(poolId);
  if (!pool) {
    pool = new ProjectPoolNFT(poolId);
    let contract = ProjectNFTStakingPoolContract.bind(getPoolAddress());
    pool.project = contract.project();
    pool.totalWeight = BigInt.fromI32(0);
    pool.whitelistCount = 0;
    pool.whitelistedNfts = [];
    pool.rewardNotifiedTotal = BigInt.fromI32(0);
    pool.claims = [];
    pool.stakerCount = 0;
    pool.stakers = [];
  }
  return pool;
}

function getOrCreateStaker(poolId: Bytes, user: Bytes): NFTStaker {
  let stakerId = poolId.concat(user);
  let staker = NFTStaker.load(stakerId);
  if (!staker) {
    staker = new NFTStaker(stakerId);
    staker.pool = poolId;
    staker.user = user;
    staker.totalWeight = BigInt.fromI32(0);
    staker.tokenIds = [];
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

export function handleNftWeightUpdated(_event: NftWeightUpdatedEvent): void {
  let pool = getOrCreatePool();
  let whitelistId = pool.id.concat(_event.params.nft);
  let whitelist = WhitelistedNFT.load(whitelistId);
  if (!whitelist) {
    whitelist = new WhitelistedNFT(whitelistId);
    whitelist.pool = pool.id;
    whitelist.nft = _event.params.nft;
    whitelist.addedBlockNumber = _event.block.number;
    whitelist.addedBlockTimestamp = _event.block.timestamp;
    whitelist.addedTransactionHash = _event.transaction.hash;
  }
  whitelist.weight = _event.params.weight;
  whitelist.updatedBlockNumber = _event.block.number;
  whitelist.updatedBlockTimestamp = _event.block.timestamp;
  whitelist.updatedTransactionHash = _event.transaction.hash;
  whitelist.save();
}

export function handleRewardTokenRemoved(
  event: RewardTokenRemovedEvent,
): void {
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

export function handleNftWhitelisted(event: NftWhitelistedEvent): void {
  let pool = getOrCreatePool();
  let whitelistId = pool.id.concat(event.params.nft);
  let whitelist = new WhitelistedNFT(whitelistId);
  whitelist.pool = pool.id;
  whitelist.nft = event.params.nft;
  whitelist.weight = event.params.weight;
  whitelist.addedBlockNumber = event.block.number;
  whitelist.addedBlockTimestamp = event.block.timestamp;
  whitelist.addedTransactionHash = event.transaction.hash;
  whitelist.save();

  let list = pool.whitelistedNfts;
  if (!list) {
    list = [];
  }
  let exists = false;
  for (let i = 0; i < list.length; i++) {
    if (list[i].equals(whitelistId)) {
      exists = true;
      break;
    }
  }
  if (!exists) {
    list.push(whitelistId);
    pool.whitelistCount = pool.whitelistCount + 1;
    pool.whitelistedNfts = list;
  }
  pool.save();
}

export function handleNftStaked(event: NftStakedEvent): void {
  let pool = getOrCreatePool();
  let staker = getOrCreateStaker(pool.id, event.params.user);
  let previous = staker.totalWeight;

  staker.totalWeight = previous.plus(event.params.weight);
  let tokens = staker.tokenIds;
  if (!tokens) {
    tokens = [];
  }
  tokens.push(event.params.tokenId);
  staker.tokenIds = tokens;
  staker.save();

  pool.totalWeight = pool.totalWeight.plus(event.params.weight);
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

export function handleNftUnstaked(event: NftUnstakedEvent): void {
  let pool = getOrCreatePool();
  let staker = getOrCreateStaker(pool.id, event.params.user);
  let previous = staker.totalWeight;
  let nextWeight = previous.minus(event.params.weight);
  staker.totalWeight = nextWeight;

  let tokens = staker.tokenIds;
  if (!tokens) {
    tokens = new Array<BigInt>();
  }
  let nextTokens = new Array<BigInt>();
  for (let i = 0; i < tokens.length; i++) {
    if (!tokens[i].equals(event.params.tokenId)) {
      nextTokens.push(tokens[i]);
    }
  }
  staker.tokenIds = nextTokens;
  staker.save();

  pool.totalWeight = pool.totalWeight.minus(event.params.weight);
  if (previous.gt(BigInt.fromI32(0)) && nextWeight.equals(BigInt.fromI32(0))) {
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
