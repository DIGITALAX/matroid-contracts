import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ClaimableCleared as ClaimableClearedEvent,
  ClaimableSet as ClaimableSetEvent,
  Claimed as ClaimedEvent,
  DistributionStarted as DistributionStartedEvent,
  EpochFinalized as EpochFinalizedEvent,
  FundsDeposited as FundsDepositedEvent,
  ProjectSlashed as ProjectSlashedEvent,
  SlashResolved as SlashResolvedEvent,
  SlashRewardNotified as SlashRewardNotifiedEvent,
  SlashingContractUpdated as SlashingContractUpdatedEvent,
  TargetDurationUpdated as TargetDurationUpdatedEvent,
  TargetReconciled as TargetReconciledEvent,
  TargetUpdated as TargetUpdatedEvent,
  Treasury,
} from "../generated/Treasury/Treasury";
import {
  ClaimableCleared,
  ClaimableSet,
  DistributionStarted,
  EpochFinalized,
  Global,
  ProjectSlash,
  SlashResolve,
  SlashRewardNotified,
  SlashingContractUpdated,
  TargetDurationUpdated,
  TargetReconciled,
  TargetUpdated,
  TreasuryClaimed,
  TreasuryDeposit,
  Claimable,
  Claimer,
  Epoch,
  Project,
} from "../generated/schema";

const GLOBAL_ID = Bytes.fromUTF8("global");

function epochId(epoch: BigInt): Bytes {
  let hex = epoch.toHexString().slice(2);
  if (hex.length % 2 == 1) {
    hex = "0" + hex;
  }
  return Bytes.fromHexString("0x" + hex);
}

function claimableId(epoch: BigInt, project: Bytes): Bytes {
  return epochId(epoch).concat(project);
}

function getOrCreateGlobal(contract: Treasury): Global {
  let global = Global.load(GLOBAL_ID);
  if (!global) {
    global = new Global(GLOBAL_ID);
    global.totalStaked = BigInt.fromI32(0);
    global.rewardNotifiedTotal = BigInt.fromI32(0);
    global.stakerCount = 0;
    global.stakers = [];
    global.epochs = [];
    global.deposits = [];
    global.in_ = new Array<Bytes>();
    global.out = new Array<Bytes>();
    global.totalDeposited = BigInt.fromI32(0);
  }
  global.targetTotal = contract.targetTotal();
  global.targetDuration = contract.targetDuration();
  global.claimWindow = contract.claimWindow();
  global.distributionStart = contract.distributionStart();
  global.totalDistributed = contract.totalDistributed();
  global.baseBudget = contract.baseBudget();
  global.perProjectBudget = contract.perProjectBudget();
  global.mona = contract.mona();
  global.registry = contract.registry();
  global.scorer = contract.scorer();
  global.globalPool = contract.globalPool();
  global.slashingContract = contract.slashingContract();
  return global;
}

export function handleClaimableCleared(event: ClaimableClearedEvent): void {
  let entity = new ClaimableCleared(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let claimableKey = claimableId(event.params.epoch, event.params.project);
  let claimable = Claimable.load(claimableKey);
  if (claimable) {
    claimable.clearedBlockNumber = event.block.number;
    claimable.clearedBlockTimestamp = event.block.timestamp;
    claimable.clearedTransactionHash = event.transaction.hash;
    claimable.save();
  }
}

export function handleClaimableSet(event: ClaimableSetEvent): void {
  let entity = new ClaimableSet(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;
  entity.amount = event.params.amount;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let claimableKey = claimableId(event.params.epoch, event.params.project);
  let claimable = Claimable.load(claimableKey);
  if (!claimable) {
    claimable = new Claimable(claimableKey);
    claimable.epoch = event.params.epoch;
    claimable.project = event.params.project;
    claimable.amount = event.params.amount;
    claimable.setBlockNumber = event.block.number;
    claimable.setBlockTimestamp = event.block.timestamp;
    claimable.setTransactionHash = event.transaction.hash;
    claimable.clearedBlockNumber = BigInt.fromI32(0);
    claimable.clearedBlockTimestamp = BigInt.fromI32(0);
    claimable.clearedTransactionHash = Bytes.fromHexString("0x");
    claimable.distributionTimestamp = BigInt.fromI32(0);
    claimable.distributionBlockNumber = BigInt.fromI32(0);
    claimable.distributionBlockTimestamp = BigInt.fromI32(0);
    claimable.distributionTransactionHash = Bytes.fromHexString("0x");
    claimable.claimers = [];
    claimable.save();
  } else {
    claimable.amount = event.params.amount;
    claimable.setBlockNumber = event.block.number;
    claimable.setBlockTimestamp = event.block.timestamp;
    claimable.setTransactionHash = event.transaction.hash;
    claimable.save();
  }

  let project = Project.load(event.params.project);
  if (project) {
    let history = project.claimableHistory;
    if (!history) {
      history = new Array<Bytes>();
    }
    let exists = false;
    for (let i = 0; i < history.length; i++) {
      if (history[i].equals(claimableKey)) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      history.push(claimableKey);
      project.claimableHistory = history;
      project.save();
    }
  }

  let epochKey = epochId(event.params.epoch);
  let epoch = Epoch.load(epochKey);
  if (!epoch) {
    epoch = new Epoch(epochKey);
    epoch.epoch = event.params.epoch;
    epoch.totalScore = BigInt.fromI32(0);
    epoch.activeProjects = BigInt.fromI32(0);
    epoch.budget = BigInt.fromI32(0);
    epoch.projects = new Array<Bytes>();
    epoch.blockNumber = event.block.number;
    epoch.blockTimestamp = event.block.timestamp;
    epoch.transactionHash = event.transaction.hash;
  }
  let projects = epoch.projects;
  if (!projects) {
    projects = new Array<Bytes>();
  }
  let projectId = event.params.project;
  let projectExists = false;
  for (let i = 0; i < projects.length; i++) {
    if (projects[i].equals(projectId)) {
      projectExists = true;
      break;
    }
  }
  if (!projectExists) {
    projects.push(projectId);
    epoch.projects = projects;
  }
  epoch.save();
}

export function handleClaimed(event: ClaimedEvent): void {
  let entity = new TreasuryClaimed(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;
  entity.claimer = event.params.claimer;
  entity.amount = event.params.amount;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let claimableKey = claimableId(event.params.epoch, event.params.project);
  let claimable = Claimable.load(claimableKey);
  if (claimable) {
    claimable.distributionTimestamp = event.block.timestamp;
    claimable.distributionBlockNumber = event.block.number;
    claimable.distributionBlockTimestamp = event.block.timestamp;
    claimable.distributionTransactionHash = event.transaction.hash;
    let claimers = claimable.claimers;
    if (!claimers) {
      claimers = new Array<Bytes>();
    }
    let claimerEntity = new Claimer(entity.id);
    claimerEntity.epoch = event.params.epoch;
    claimerEntity.project = event.params.project;
    claimerEntity.claimer = event.params.claimer;
    claimerEntity.amount = event.params.amount;
    claimerEntity.blockNumber = event.block.number;
    claimerEntity.blockTimestamp = event.block.timestamp;
    claimerEntity.transactionHash = event.transaction.hash;
    claimerEntity.save();
    claimers.push(claimerEntity.id);
    claimable.claimers = claimers;
    claimable.save();
  }
}

export function handleDistributionStarted(
  event: DistributionStartedEvent,
): void {
  let entity = new DistributionStarted(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.timestamp = event.params.timestamp;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleEpochFinalized(event: EpochFinalizedEvent): void {
  let entity = new EpochFinalized(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.epoch = event.params.epoch;
  entity.totalScore = event.params.totalScore;
  entity.activeProjects = event.params.activeProjects;
  entity.budget = event.params.budget;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let epochKey = epochId(event.params.epoch);
  let epoch = Epoch.load(epochKey);
  if (!epoch) {
    epoch = new Epoch(epochKey);
    epoch.epoch = event.params.epoch;
    epoch.projects = new Array<Bytes>();
  }
  epoch.totalScore = event.params.totalScore;
  epoch.activeProjects = event.params.activeProjects;
  epoch.budget = event.params.budget;
  epoch.blockNumber = event.block.number;
  epoch.blockTimestamp = event.block.timestamp;
  epoch.transactionHash = event.transaction.hash;
  epoch.save();

  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);
  let epochs = global.epochs;
  if (!epochs) {
    epochs = new Array<Bytes>();
  }
  let exists = false;
  for (let i = 0; i < epochs.length; i++) {
    if (epochs[i].equals(epochKey)) {
      exists = true;
      break;
    }
  }
  if (!exists) {
    epochs.push(epochKey);
    global.epochs = epochs;
    global.save();
  }
}

export function handleFundsDeposited(event: FundsDepositedEvent): void {
  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);

  let deposits = global.deposits;
  if (!deposits) {
    deposits = [];
  }

  let newDeposit = new TreasuryDeposit(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );

  newDeposit.from = event.params.from;
  newDeposit.amount = event.params.amount;
  newDeposit.blockNumber = event.block.number;
  newDeposit.blockTimestamp = event.block.timestamp;
  newDeposit.transactionHash = event.transaction.hash;
  newDeposit.save();

  deposits.push(newDeposit.id);

  global.deposits = deposits;
  let total = global.totalDeposited;
  if (!total) {
    total = BigInt.fromI32(0);
  }
  global.totalDeposited = total.plus(event.params.amount);

  global.save();
}

export function handleProjectSlashed(event: ProjectSlashedEvent): void {
  let entityId = claimableId(event.params.epoch, event.params.project);
  let entity = new ProjectSlash(entityId);
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;
  entity.slashBps = event.params.slashBps;
  entity.blacklisted = event.params.blacklisted;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleSlashResolved(event: SlashResolvedEvent): void {
  let entityId = claimableId(event.params.epoch, event.params.project);
  let entity = new SlashResolve(entityId);
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;
  entity.voterReward = event.params.voterReward;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();

  let slash = ProjectSlash.load(entityId);
  if (slash) {
    slash.resolve = entity.id;
    slash.save();
  }
}

export function handleSlashRewardNotified(
  event: SlashRewardNotifiedEvent,
): void {
  let entity = new SlashRewardNotified(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.epoch = event.params.epoch;
  entity.project = event.params.project;
  entity.amount = event.params.amount;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleSlashingContractUpdated(
  event: SlashingContractUpdatedEvent,
): void {
  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);
  global.save();

  let entity = new SlashingContractUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.oldContract = event.params.oldContract;
  entity.newContract = event.params.newContract;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();
}

export function handleTargetDurationUpdated(
  event: TargetDurationUpdatedEvent,
): void {
  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);
  global.save();

  let entity = new TargetDurationUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.oldDuration = event.params.oldDuration;
  entity.newDuration = event.params.newDuration;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();
}

export function handleTargetReconciled(event: TargetReconciledEvent): void {
  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);
  global.save();

  let entity = new TargetReconciled(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.oldTarget = event.params.oldTarget;
  entity.newTarget = event.params.newTarget;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();
}

export function handleTargetUpdated(event: TargetUpdatedEvent): void {
  let contract = Treasury.bind(event.address);
  let global = getOrCreateGlobal(contract);
  global.save();

  let entity = new TargetUpdated(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  );
  entity.oldTarget = event.params.oldTarget;
  entity.newTarget = event.params.newTarget;
  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;
  entity.save();
}
