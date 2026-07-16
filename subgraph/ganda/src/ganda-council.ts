import { BigInt } from "@graphprotocol/graph-ts";
import {
  Proposed as ProposedEvent,
  Voted as VotedEvent,
  Executed as ExecutedEvent,
  PaymasterSet as PaymasterSetEvent,
} from "../generated/GandaCouncil/GandaCouncil";
import { Proposal, Vote, GandaConfig } from "../generated/schema";

export function handleProposed(event: ProposedEvent): void {
  const proposal = new Proposal(event.params.proposalId.toString());
  proposal.proposalId = event.params.proposalId;
  proposal.kind = event.params.kind;
  proposal.target = event.params.target;
  proposal.tagTarget = event.params.tagTarget;
  proposal.value = event.params.value;
  proposal.uri = event.params.uri;
  proposal.yes = BigInt.zero();
  proposal.no = BigInt.zero();
  proposal.start = event.block.timestamp;
  proposal.end = BigInt.zero();
  proposal.executed = false;
  proposal.passed = false;
  proposal.save();
}

export function handleVoted(event: VotedEvent): void {
  const proposalId = event.params.proposalId.toString();
  const vote = new Vote(
    proposalId + "-" + event.params.nullifier.toHexString(),
  );
  vote.proposal = proposalId;
  vote.nullifier = event.params.nullifier;
  vote.support = event.params.support;
  vote.timestamp = event.block.timestamp;
  vote.save();

  const proposal = Proposal.load(proposalId);
  if (proposal == null) return;
  if (event.params.support) {
    proposal.yes = proposal.yes.plus(BigInt.fromI32(1));
  } else {
    proposal.no = proposal.no.plus(BigInt.fromI32(1));
  }
  proposal.save();
}

export function handleExecuted(event: ExecutedEvent): void {
  const proposal = Proposal.load(event.params.proposalId.toString());
  if (proposal == null) return;
  proposal.executed = true;
  proposal.passed = event.params.passed;
  proposal.end = event.block.timestamp;
  proposal.save();
}

export function handlePaymasterSet(event: PaymasterSetEvent): void {
  let config = GandaConfig.load("ganda");
  if (config == null) {
    config = new GandaConfig("ganda");
    config.metadata = "";
    config.globalBps = 0;
    config.projectBps = 0;
    config.nftBps = 0;
    config.potBps = 0;
    config.gamesPotBps = 0;
    config.claimWindowEpochs = BigInt.zero();
    config.paymasterDefaultCap = BigInt.zero();
  }
  config.paymaster = event.params.paymaster;
  config.save();
}
