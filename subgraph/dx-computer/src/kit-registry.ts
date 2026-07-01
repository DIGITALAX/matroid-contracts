import { BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import {
  KitPublished as KitPublishedEvent,
  KitVersioned as KitVersionedEvent,
  KitRemoved as KitRemovedEvent,
} from "../generated/KitRegistry/KitRegistry";
import { Kit, KitVersion } from "../generated/schema";

const ZERO_HASH = Bytes.fromHexString(
  "0x0000000000000000000000000000000000000000000000000000000000000000",
);

function isCleanUri(uri: string): boolean {
  return (
    uri.startsWith("ipfs://") ||
    uri.startsWith("https://") ||
    uri.startsWith("ar://")
  );
}

function saveVersion(
  kitId: string,
  version: BigInt,
  designHash: Bytes,
  contentUri: string,
  event: ethereum.Event,
): void {
  let v = new KitVersion(kitId + "-" + version.toString());
  v.kit = kitId;
  v.version = version;
  v.designHash = designHash;
  v.contentUri = contentUri;
  v.createdAtBlock = event.block.number;
  v.createdAtTimestamp = event.block.timestamp;
  v.transactionHash = event.transaction.hash;
  v.save();
}

export function handleKitPublished(event: KitPublishedEvent): void {
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  let kit = new Kit(event.params.id.toString());
  kit.kitId = event.params.id;
  kit.parentId = event.params.parentId;
  kit.mode = event.params.mode;
  kit.designHash = event.params.designHash;
  kit.contentUri = event.params.contentUri;
  kit.version = BigInt.fromI32(0);
  kit.revoked = false;
  kit.createdAtBlock = event.block.number;
  kit.createdAtTimestamp = event.block.timestamp;
  kit.updatedAtBlock = event.block.number;
  kit.updatedAtTimestamp = event.block.timestamp;
  kit.transactionHash = event.transaction.hash;
  kit.save();

  saveVersion(
    event.params.id.toString(),
    BigInt.fromI32(0),
    event.params.designHash,
    event.params.contentUri,
    event,
  );
}

export function handleKitVersioned(event: KitVersionedEvent): void {
  let kit = Kit.load(event.params.id.toString());
  if (kit == null) {
    return;
  }
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  kit.designHash = event.params.designHash;
  kit.contentUri = event.params.contentUri;
  kit.version = event.params.version;
  kit.updatedAtBlock = event.block.number;
  kit.updatedAtTimestamp = event.block.timestamp;
  kit.save();

  saveVersion(
    event.params.id.toString(),
    event.params.version,
    event.params.designHash,
    event.params.contentUri,
    event,
  );
}

export function handleKitRemoved(event: KitRemovedEvent): void {
  let kit = Kit.load(event.params.id.toString());
  if (kit == null) {
    return;
  }
  kit.revoked = true;
  kit.designHash = ZERO_HASH;
  kit.contentUri = "";
  kit.updatedAtBlock = event.block.number;
  kit.updatedAtTimestamp = event.block.timestamp;
  kit.save();
}
