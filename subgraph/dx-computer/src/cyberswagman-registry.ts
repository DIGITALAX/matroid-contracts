import { store } from "@graphprotocol/graph-ts";
import {
  AgentRegistered as AgentRegisteredEvent,
  AgentUpdated as AgentUpdatedEvent,
  SchemaChanged as SchemaChangedEvent,
  ResultPosted as ResultPostedEvent,
  AgentDeleted as AgentDeletedEvent,
} from "../generated/CyberswagmanRegistry/CyberswagmanRegistry";
import { Agent, AgentKit, AgentResult } from "../generated/schema";

function isCleanUri(uri: string): boolean {
  return (
    uri.startsWith("ipfs://") ||
    uri.startsWith("https://") ||
    uri.startsWith("ar://")
  );
}

export function handleAgentRegistered(event: AgentRegisteredEvent): void {
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  let agent = new Agent(event.params.agentId.toString());
  agent.agentId = event.params.agentId;
  agent.owner = event.params.owner;
  agent.modelHash = event.params.modelHash;
  agent.hardwareHash = event.params.hardwareHash;
  agent.contentUri = event.params.contentUri;
  agent.createdAtBlock = event.block.number;
  agent.createdAtTimestamp = event.block.timestamp;
  agent.transactionHash = event.transaction.hash;
  agent.save();
}

export function handleAgentUpdated(event: AgentUpdatedEvent): void {
  let agent = Agent.load(event.params.agentId.toString());
  if (agent == null) {
    return;
  }
  agent.modelHash = event.params.modelHash;
  agent.hardwareHash = event.params.hardwareHash;
  if (isCleanUri(event.params.contentUri)) {
    agent.contentUri = event.params.contentUri;
  }
  agent.save();
}

export function handleSchemaChanged(event: SchemaChangedEvent): void {
  let id =
    event.params.agentId.toString() + "-" + event.params.kitId.toString();
  let link = AgentKit.load(id);
  if (link == null) {
    link = new AgentKit(id);
    link.agent = event.params.agentId.toString();
    link.kit = event.params.kitId.toString();
    link.kitId = event.params.kitId;
  }
  link.included = event.params.included;
  link.save();
}

export function handleResultPosted(event: ResultPostedEvent): void {
  let id =
    event.params.agentId.toString() +
    "-" +
    event.params.projectId.toString() +
    "-" +
    event.transaction.hash.toHexString() +
    "-" +
    event.logIndex.toString();
  let r = new AgentResult(id);
  r.agent = event.params.agentId.toString();
  r.kitId = event.params.projectId;
  r.contentUri = "";
  r.resultHash = event.params.resultHash;
  if (isCleanUri(event.params.contentUri)) {
    r.contentUri = event.params.contentUri;
  }
  r.createdAtBlock = event.block.number;
  r.createdAtTimestamp = event.block.timestamp;
  r.transactionHash = event.transaction.hash;
  r.save();
}

export function handleAgentDeleted(event: AgentDeletedEvent): void {
  store.remove("Agent", event.params.agentId.toString());
}
