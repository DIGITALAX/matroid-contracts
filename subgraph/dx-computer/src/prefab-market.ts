import { BigInt } from "@graphprotocol/graph-ts";
import {
  OfferCreated as OfferCreatedEvent,
  OfferUpdated as OfferUpdatedEvent,
  OfferDeleted as OfferDeletedEvent,
  GrantLinked as GrantLinkedEvent,
  OrderPlaced as OrderPlacedEvent,
} from "../generated/PrefabMarket/PrefabMarket";
import { Offer } from "../generated/schema";

function isCleanUri(uri: string): boolean {
  return (
    uri.startsWith("ipfs://") ||
    uri.startsWith("https://") ||
    uri.startsWith("ar://")
  );
}

export function handleOfferCreated(event: OfferCreatedEvent): void {
  if (!isCleanUri(event.params.contentUri)) {
    return;
  }
  let offer = new Offer(event.params.offerId.toString());
  offer.offerId = event.params.offerId;
  offer.fabricator = event.params.fabricator;
  offer.kitId = event.params.kitId;
  offer.kit = event.params.kitId.toString();
  offer.version = BigInt.fromI64(event.params.version);
  offer.designHash = event.params.designHash;
  offer.contentUri = event.params.contentUri;
  offer.price = event.params.price;
  offer.sliceBps = event.params.sliceBps;
  offer.quantity = event.params.quantity;
  offer.grantId = BigInt.fromI32(0);
  offer.grantBps = 0;
  offer.grantLinked = false;
  offer.exists = true;
  offer.createdAtBlock = event.block.number;
  offer.createdAtTimestamp = event.block.timestamp;
  offer.transactionHash = event.transaction.hash;
  offer.save();
}

export function handleOfferUpdated(event: OfferUpdatedEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  offer.price = event.params.price;
  offer.sliceBps = event.params.sliceBps;
  offer.quantity = event.params.quantity;
  offer.save();
}

export function handleOfferDeleted(event: OfferDeletedEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  offer.exists = false;
  offer.save();
}

export function handleGrantLinked(event: GrantLinkedEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  offer.grantId = event.params.grantId;
  offer.grantBps = event.params.grantBps;
  offer.grantLinked = true;
  offer.save();
}

export function handleOrderPlaced(event: OrderPlacedEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  if (offer.quantity.gt(BigInt.fromI32(0))) {
    offer.quantity = offer.quantity.minus(BigInt.fromI32(1));
  }
  offer.save();
}
