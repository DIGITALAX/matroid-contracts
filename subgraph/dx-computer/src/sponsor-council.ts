import { Address, BigInt } from "@graphprotocol/graph-ts";
import {
  SponsorCouncil,
  ProposalCreated as ProposalCreatedEvent,
  Voted as VotedEvent,
  Executed as ExecutedEvent,
} from "../generated/SponsorCouncil/SponsorCouncil";
import { CouncilProposal } from "../generated/schema";

export function handleProposalCreated(event: ProposalCreatedEvent): void {
  let p = new CouncilProposal(event.params.id.toString());
  p.proposalId = event.params.id;
  p.kind = event.params.kind;
  p.contentUri = event.params.contentUri;
  p.project = event.params.project;
  p.banned = event.params.banned;
  p.value = event.params.value;
  p.end = event.params.end;
  p.target = Address.zero();
  p.extra = BigInt.fromI32(0);
  p.start = event.block.timestamp;

  let council = SponsorCouncil.bind(event.address);
  let res = council.try_proposals(event.params.id);
  if (!res.reverted) {
    p.target = res.value.getTarget();
    p.extra = res.value.getExtra();
    p.start = res.value.getStart();
    p.end = res.value.getEnd();
  }

  p.yes = BigInt.fromI32(0);
  p.no = BigInt.fromI32(0);
  p.executed = false;
  p.createdAtBlock = event.block.number;
  p.createdAtTimestamp = event.block.timestamp;
  p.transactionHash = event.transaction.hash;
  p.save();
}

export function handleVoted(event: VotedEvent): void {
  let p = CouncilProposal.load(event.params.id.toString());
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
  let p = CouncilProposal.load(event.params.id.toString());
  if (p == null) {
    return;
  }
  p.executed = true;
  p.save();
}
