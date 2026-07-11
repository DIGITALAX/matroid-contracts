import { BigInt, store } from "@graphprotocol/graph-ts";
import {
  OfferCreated as OfferCreatedEvent,
  OfferUpdated as OfferUpdatedEvent,
  OfferDeleted as OfferDeletedEvent,
  GrantLinked as GrantLinkedEvent,
  GrantUnlinked as GrantUnlinkedEvent,
  AgentLinked as AgentLinkedEvent,
  AgentUnlinked as AgentUnlinkedEvent,
  CyberSwagSet as CyberSwagSetEvent,
  OrderPlaced as OrderPlacedEvent,
  OrderSlices as OrderSlicesEvent,
  OrderReleased as OrderReleasedEvent,
  OrderRefunded as OrderRefundedEvent,
  OrderStageSet as OrderStageSetEvent,
} from "../generated/PrefabMarket/PrefabMarket";
import { Offer, OfferAgent, Order } from "../generated/schema";

function isCleanUri(uri: string): bool {
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
  offer.version = event.params.version;
  offer.designHash = event.params.designHash;
  offer.contentUri = event.params.contentUri;
  offer.price = event.params.price;
  offer.sliceBps = event.params.sliceBps;
  offer.quantity = event.params.quantity;
  offer.grantId = BigInt.fromI32(0);
  offer.grantBps = 0;
  offer.grantLinked = false;
  offer.cyberSwagBps = 0;
  offer.confirmWindow = event.params.confirmWindow;
  offer.exists = true;
  offer.createdAtBlock = event.block.number;
  offer.createdAtTimestamp = event.block.timestamp;
  offer.updatedAtBlock = event.block.number;
  offer.updatedAtTimestamp = event.block.timestamp;
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
  if (isCleanUri(event.params.contentUri)) {
    offer.contentUri = event.params.contentUri;
  }
  offer.confirmWindow = event.params.confirmWindow;
  offer.updatedAtBlock = event.block.number;
  offer.updatedAtTimestamp = event.block.timestamp;
  offer.transactionHash = event.transaction.hash;
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
  offer.updatedAtBlock = event.block.number;
  offer.updatedAtTimestamp = event.block.timestamp;
  offer.transactionHash = event.transaction.hash;
  offer.save();
}

export function handleGrantUnlinked(event: GrantUnlinkedEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  offer.grantId = BigInt.fromI32(0);
  offer.grantBps = 0;
  offer.grantLinked = false;
  offer.updatedAtBlock = event.block.number;
  offer.updatedAtTimestamp = event.block.timestamp;
  offer.transactionHash = event.transaction.hash;
  offer.save();
}

export function handleCyberSwagSet(event: CyberSwagSetEvent): void {
  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  offer.cyberSwagBps = event.params.cyberSwagBps;
  offer.updatedAtBlock = event.block.number;
  offer.updatedAtTimestamp = event.block.timestamp;
  offer.transactionHash = event.transaction.hash;
  offer.save();
}

export function handleAgentLinked(event: AgentLinkedEvent): void {
  let id =
    event.params.offerId.toString() + "-" + event.params.agentId.toString();
  let link = new OfferAgent(id);
  link.offer = event.params.offerId.toString();
  link.offerId = event.params.offerId;
  link.agentId = event.params.agentId;
  link.createdAtTimestamp = event.block.timestamp;
  link.transactionHash = event.transaction.hash;
  link.save();
}

export function handleAgentUnlinked(event: AgentUnlinkedEvent): void {
  let id =
    event.params.offerId.toString() + "-" + event.params.agentId.toString();
  store.remove("OfferAgent", id);
}

export function handleOrderPlaced(event: OrderPlacedEvent): void {
  let order = new Order(event.params.orderId.toString());
  order.orderId = event.params.orderId;
  order.offerId = event.params.offerId;
  order.offer = event.params.offerId.toString();
  order.buyer = event.params.buyer;
  order.oracle = event.params.oracle;
  order.quantity = event.params.quantity;
  order.shippingCommitment = event.params.shippingCommitment;
  order.encryptedShipping = event.params.encryptedShipping;
  order.status = "open";
  order.stage = 0;
  order.deadline = BigInt.fromI32(0);
  order.total = BigInt.fromI32(0);
  order.slice = BigInt.fromI32(0);
  order.grantSlice = BigInt.fromI32(0);
  order.cyberSlice = BigInt.fromI32(0);
  order.grantId = BigInt.fromI32(0);
  order.createdAtBlock = event.block.number;
  order.createdAtTimestamp = event.block.timestamp;
  order.updatedAtTimestamp = event.block.timestamp;
  order.transactionHash = event.transaction.hash;
  order.save();

  let offer = Offer.load(event.params.offerId.toString());
  if (offer == null) {
    return;
  }
  if (offer.quantity.ge(event.params.quantity)) {
    offer.quantity = offer.quantity.minus(event.params.quantity);
  } else {
    offer.quantity = BigInt.fromI32(0);
  }
  offer.save();
}

export function handleOrderReleased(event: OrderReleasedEvent): void {
  let order = Order.load(event.params.orderId.toString());
  if (order == null) {
    return;
  }
  order.status = "completed";
  order.updatedAtTimestamp = event.block.timestamp;
  order.save();
}

export function handleOrderRefunded(event: OrderRefundedEvent): void {
  let order = Order.load(event.params.orderId.toString());
  if (order == null) {
    return;
  }
  order.status = "refunded";
  order.updatedAtTimestamp = event.block.timestamp;
  order.save();
}

export function handleOrderStageSet(event: OrderStageSetEvent): void {
  let order = Order.load(event.params.orderId.toString());
  if (order == null) {
    return;
  }
  order.stage = event.params.stage;
  order.deadline = event.params.deadline;
  order.updatedAtTimestamp = event.block.timestamp;
  order.save();
}

export function handleOrderSlices(event: OrderSlicesEvent): void {
  let order = Order.load(event.params.orderId.toString());
  if (order == null) {
    return;
  }
  order.total = event.params.total;
  order.slice = event.params.slice;
  order.grantSlice = event.params.grantSlice;
  order.cyberSlice = event.params.cyberSlice;
  order.grantId = event.params.grantId;
  order.save();
}
