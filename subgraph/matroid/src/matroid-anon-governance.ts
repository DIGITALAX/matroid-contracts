import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  ProposalCreated as ProposalCreatedEvent,
  Voted as VotedEvent,
  Executed as ExecutedEvent,
} from "../generated/MatroidAnonGovernance/MatroidAnonGovernance";
import { AnonBudgetProposal } from "../generated/schema";

function proposalId(id: BigInt): Bytes {
  return Bytes.fromHexString(id.toHexString());
}

export function handleProposalCreated(event: ProposalCreatedEvent): void {
  let p = new AnonBudgetProposal(proposalId(event.params.id));
  p.proposalId = event.params.id;
  p.baseBudget = event.params.baseBudget;
  p.perProjectBudget = event.params.perProjectBudget;
  p.newDuration = event.params.newDuration;
  p.end = BigInt.fromI32(event.params.end);
  p.yes = BigInt.fromI32(0);
  p.no = BigInt.fromI32(0);
  p.executed = false;
  p.blockNumber = event.block.number;
  p.blockTimestamp = event.block.timestamp;
  p.transactionHash = event.transaction.hash;
  p.save();
}

export function handleVoted(event: VotedEvent): void {
  let p = AnonBudgetProposal.load(proposalId(event.params.id));
  if (p == null) {
    return;
  }
  if (event.params.choice == 1) {
    p.yes = p.yes.plus(BigInt.fromI32(1));
  } else {
    p.no = p.no.plus(BigInt.fromI32(1));
  }
  p.save();
}

export function handleExecuted(event: ExecutedEvent): void {
  let p = AnonBudgetProposal.load(proposalId(event.params.id));
  if (p == null) {
    return;
  }
  p.executed = true;
  p.passed = event.params.passed;
  p.applied = event.params.applied;
  p.save();
}
