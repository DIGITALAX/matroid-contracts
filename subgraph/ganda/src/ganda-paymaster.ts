import { BigInt } from "@graphprotocol/graph-ts";
import {
  CoreTargetSet as CoreTargetSetEvent,
  GameTargetRegistered as GameTargetRegisteredEvent,
  CapSet as CapSetEvent,
  DefaultCapSet as DefaultCapSetEvent,
  SponsoredCall as SponsoredCallEvent,
} from "../generated/GandaPaymaster/GandaPaymaster";
import { PaymasterTarget, SponsoredCall, GandaConfig } from "../generated/schema";

function loadTarget(id: string): PaymasterTarget {
  let target = PaymasterTarget.load(id);
  if (target == null) {
    target = new PaymasterTarget(id);
    target.gameId = BigInt.zero();
    target.core = false;
    target.active = false;
    target.cap = BigInt.zero();
  }
  return target;
}

export function handleCoreTargetSet(event: CoreTargetSetEvent): void {
  const target = loadTarget(event.params.target.toHexString());
  target.target = event.params.target;
  target.core = event.params.active;
  target.active = event.params.active;
  target.save();
}

export function handleGameTargetRegistered(
  event: GameTargetRegisteredEvent,
): void {
  const target = loadTarget(event.params.target.toHexString());
  target.target = event.params.target;
  target.gameId = event.params.gameId;
  target.active = event.params.active;
  target.save();
}

export function handleCapSet(event: CapSetEvent): void {
  const target = loadTarget(event.params.target.toHexString());
  target.target = event.params.target;
  target.cap = event.params.cap;
  target.save();
}

export function handleDefaultCapSet(event: DefaultCapSetEvent): void {
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
  }
  config.paymasterDefaultCap = event.params.cap;
  config.save();
}

export function handleSponsoredCall(event: SponsoredCallEvent): void {
  const call = new SponsoredCall(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  call.target = event.params.target;
  call.from = event.params.from;
  call.fee = event.params.fee;
  call.epoch = event.params.epoch;
  call.timestamp = event.block.timestamp;
  call.save();
}
