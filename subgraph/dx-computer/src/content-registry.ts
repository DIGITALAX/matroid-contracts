import { Address } from "@graphprotocol/graph-ts";
import {
  Posted as PostedEvent,
  Updated as UpdatedEvent,
} from "../generated/ContentRegistry/ContentRegistry";
import { Content } from "../generated/schema";

function isCleanUri(uri: string): boolean {
  return (
    uri.startsWith("ipfs://") ||
    uri.startsWith("https://") ||
    uri.startsWith("ar://")
  );
}

export function handlePosted(event: PostedEvent): void {
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  let content = new Content(event.params.id.toString());
  content.contentId = event.params.id;
  content.author = event.params.author;
  content.ownerTag = event.params.ownerTag;
  content.canonicalTag = event.params.canonicalTag;
  content.contentHash = event.params.contentHash;
  content.contentUri = event.params.contentUri;
  content.anonymous = event.params.author.equals(Address.zero());
  content.revoked = false;
  content.createdAtBlock = event.block.number;
  content.createdAtTimestamp = event.block.timestamp;
  content.transactionHash = event.transaction.hash;
  content.save();
}

export function handleUpdated(event: UpdatedEvent): void {
  let content = Content.load(event.params.id.toString());
  if (content == null) {
    return;
  }
  content.contentHash = event.params.contentHash;
  content.revoked = event.params.revoked;
  content.save();
}
