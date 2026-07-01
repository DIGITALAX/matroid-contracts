import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ProposalCreated as ProposalCreatedEvent,
  Voted as VotedEvent,
  ProposalExecuted as ProposalExecutedEvent,
} from "../generated/MatroidGovernance/MatroidGovernance";
import { BudgetProposal, BudgetVote } from "../generated/schema";

function proposalId(id: BigInt): Bytes {
  return Bytes.fromHexString(id.toHexString());
}

export function handleProposalCreated(event: ProposalCreatedEvent): void {
  let p = new BudgetProposal(proposalId(event.params.id));
  p.proposalId = event.params.id;
  p.baseBudget = event.params.baseBudget;
  p.perProjectBudget = event.params.perProjectBudget;
  p.newDuration = BigInt.fromI32(0);
  p.endTime = event.params.endTime;
  p.yesWeight = BigInt.fromI32(0);
  p.noWeight = BigInt.fromI32(0);
  p.executed = false;
  p.blockNumber = event.block.number;
  p.blockTimestamp = event.block.timestamp;
  p.transactionHash = event.transaction.hash;
  p.save();
}

export function handleVoted(event: VotedEvent): void {
  let p = BudgetProposal.load(proposalId(event.params.id));
  if (p == null) {
    return;
  }
  if (event.params.inFavor) {
    p.yesWeight = p.yesWeight.plus(event.params.amount);
  } else {
    p.noWeight = p.noWeight.plus(event.params.amount);
  }
  p.save();

  let voteId = proposalId(event.params.id).concat(event.transaction.hash);
  let v = new BudgetVote(voteId);
  v.proposal = p.id;
  v.voter = event.params.voter;
  v.inFavor = event.params.inFavor;
  v.amount = event.params.amount;
  v.blockNumber = event.block.number;
  v.blockTimestamp = event.block.timestamp;
  v.transactionHash = event.transaction.hash;
  v.save();
}

export function handleProposalExecuted(event: ProposalExecutedEvent): void {
  let p = BudgetProposal.load(proposalId(event.params.id));
  if (p == null) {
    return;
  }
  p.executed = true;
  p.passed = event.params.passed;
  p.applied = event.params.applied;
  p.save();
}
