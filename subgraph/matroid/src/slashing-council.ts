import {
  ProposalExecuted as ProposalExecutedEvent,
  ProposalResolved as ProposalResolvedEvent,
  Voted as VotedEvent,
  VoterRewardNotified as VoterRewardNotifiedEvent,
  VoterRewarded as VoterRewardedEvent,
} from "../generated/SlashingCouncil/SlashingCouncil"
import {
  Proposal,
  ProposalExecuted,
  ProposalResolved,
  ProjectSlash,
  Voter,
  Voted,
  VoterRewardNotified,
  VoterRewarded,
  Claimable,
} from "../generated/schema"
import { BigInt, Bytes } from "@graphprotocol/graph-ts"

function epochId(epoch: BigInt): Bytes {
  let hex = epoch.toHexString().slice(2);
  if (hex.length % 2 == 1) {
    hex = "0" + hex;
  }
  return Bytes.fromHexString("0x" + hex);
}

function proposalId(epoch: BigInt, project: Bytes): Bytes {
  return epochId(epoch).concat(project);
}

function voterId(epoch: BigInt, project: Bytes, voter: Bytes): Bytes {
  return epochId(epoch).concat(project).concat(voter);
}

export function handleProposalExecuted(event: ProposalExecutedEvent): void {
  let proposalKey = proposalId(event.params.epoch, event.params.project);
  let proposal = Proposal.load(proposalKey);
  if (!proposal) {
    proposal = new Proposal(proposalKey);
    proposal.epoch = event.params.epoch;
    proposal.project = event.params.project;
    proposal.voters = [];
  }
  proposal.slashBps = event.params.slashBps;
  proposal.blacklist = event.params.blacklist;
  proposal.blockNumber = event.block.number;
  proposal.blockTimestamp = event.block.timestamp;
  proposal.transactionHash = event.transaction.hash;
  let slash = ProjectSlash.load(proposalKey);
  if (slash) {
    proposal.slash = slash.id;
  }
  proposal.save();

  let claimable = Claimable.load(proposalKey);
  if (claimable) {
    claimable.proposal = proposal.id;
    claimable.save();
  }

  let entity = new ProposalExecuted(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.epoch = event.params.epoch
  entity.project = event.params.project
  entity.slashBps = event.params.slashBps
  entity.blacklist = event.params.blacklist

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleProposalResolved(event: ProposalResolvedEvent): void {
  let proposalKey = proposalId(event.params.epoch, event.params.project);
  let proposal = Proposal.load(proposalKey);
  if (!proposal) {
    proposal = new Proposal(proposalKey);
    proposal.epoch = event.params.epoch;
    proposal.project = event.params.project;
    proposal.voters = [];
    proposal.slashBps = 0;
    proposal.blacklist = false;
  }

  let entity = new ProposalResolved(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.epoch = event.params.epoch
  entity.project = event.params.project
  entity.passed = event.params.passed

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()

  proposal.resolved = entity.id;
  proposal.save();
}

export function handleVoted(event: VotedEvent): void {
  let voterKey = voterId(event.params.epoch, event.params.project, event.params.voter);
  let voter = Voter.load(voterKey);
  if (!voter) {
    voter = new Voter(voterKey);
    voter.epoch = event.params.epoch;
    voter.project = event.params.project;
    voter.voter = event.params.voter;
    voter.rewardAmount = null;
    voter.rewardBlockNumber = BigInt.fromI32(0);
    voter.rewardBlockTimestamp = BigInt.fromI32(0);
    voter.rewardTransactionHash = Bytes.fromHexString("0x");
  }
  voter.weight = event.params.weight;
  voter.blockNumber = event.block.number;
  voter.blockTimestamp = event.block.timestamp;
  voter.transactionHash = event.transaction.hash;
  voter.save();

  let proposalKey = proposalId(event.params.epoch, event.params.project);
  let proposal = Proposal.load(proposalKey);
  if (proposal) {
    let voters = proposal.voters;
    if (!voters) {
      voters = [];
    }
    let exists = false;
    for (let i = 0; i < voters.length; i++) {
      if (voters[i].equals(voter.id)) {
        exists = true;
        break;
      }
    }
    if (!exists) {
      voters.push(voter.id);
      proposal.voters = voters;
      proposal.save();
    }
  }

  let entity = new Voted(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.epoch = event.params.epoch
  entity.project = event.params.project
  entity.voter = event.params.voter
  entity.weight = event.params.weight

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleVoterRewardNotified(
  event: VoterRewardNotifiedEvent,
): void {
  let entity = new VoterRewardNotified(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.epoch = event.params.epoch
  entity.project = event.params.project
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}

export function handleVoterRewarded(event: VoterRewardedEvent): void {
  let voterKey = voterId(event.params.epoch, event.params.project, event.params.voter);
  let voter = Voter.load(voterKey);
  if (!voter) {
    voter = new Voter(voterKey);
    voter.epoch = event.params.epoch;
    voter.project = event.params.project;
    voter.voter = event.params.voter;
    voter.weight = BigInt.fromI32(0);
  }
  voter.rewardAmount = event.params.amount;
  voter.rewardBlockNumber = event.block.number;
  voter.rewardBlockTimestamp = event.block.timestamp;
  voter.rewardTransactionHash = event.transaction.hash;
  voter.save();

  let entity = new VoterRewarded(
    event.transaction.hash.concatI32(event.logIndex.toI32()),
  )
  entity.epoch = event.params.epoch
  entity.project = event.params.project
  entity.voter = event.params.voter
  entity.amount = event.params.amount

  entity.blockNumber = event.block.number
  entity.blockTimestamp = event.block.timestamp
  entity.transactionHash = event.transaction.hash

  entity.save()
}
