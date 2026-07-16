import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  Bootstrapped as BootstrappedEvent,
  FlowIn as FlowInEvent,
  FlowOut as FlowOutEvent,
  PotFunded as PotFundedEvent,
  SplitsSet as SplitsSetEvent,
  ScoreSet as ScoreSetEvent,
} from "../generated/GandaHub/GandaHub";
import { Flow, GameEpoch, GandaConfig } from "../generated/schema";

function loadConfig(): GandaConfig {
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
  return config;
}

function loadGameEpoch(epoch: BigInt, gameId: BigInt): GameEpoch {
  const id = epoch.toString() + "-" + gameId.toString();
  let gameEpoch = GameEpoch.load(id);
  if (gameEpoch == null) {
    gameEpoch = new GameEpoch(id);
    gameEpoch.game = gameId.toString();
    gameEpoch.epoch = epoch;
    gameEpoch.volumeIn = BigInt.zero();
    gameEpoch.volumeOut = BigInt.zero();
    gameEpoch.flowCount = BigInt.zero();
    gameEpoch.potFunded = BigInt.zero();
    gameEpoch.totalPoints = BigInt.zero();
    gameEpoch.playerCount = BigInt.zero();
    gameEpoch.potClaimed = false;
    gameEpoch.potClaimAmount = BigInt.zero();
  }
  return gameEpoch;
}

export function handleBootstrapped(event: BootstrappedEvent): void {
  const config = loadConfig();
  config.metadata = event.params.metadata;
  config.globalBps = event.params.globalBps;
  config.projectBps = event.params.projectBps;
  config.nftBps = event.params.nftBps;
  config.potBps = event.params.potBps;
  config.save();
}

export function handleFlowIn(event: FlowInEvent): void {
  const flow = new Flow(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  flow.game = event.params.gameId.toString();
  flow.isIn = true;
  flow.wallet = event.params.player;
  flow.amount = event.params.amount;
  flow.destination = event.params.destination;
  flow.epoch = event.params.epoch;
  flow.timestamp = event.block.timestamp;
  flow.txHash = event.transaction.hash;
  flow.save();

  const gameEpoch = loadGameEpoch(event.params.epoch, event.params.gameId);
  gameEpoch.volumeIn = gameEpoch.volumeIn.plus(event.params.amount);
  gameEpoch.flowCount = gameEpoch.flowCount.plus(BigInt.fromI32(1));
  gameEpoch.save();
}

export function handleFlowOut(event: FlowOutEvent): void {
  const flow = new Flow(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  flow.game = event.params.gameId.toString();
  flow.isIn = false;
  flow.wallet = event.params.recipient;
  flow.amount = event.params.amount;
  flow.destination = null;
  flow.epoch = event.params.epoch;
  flow.timestamp = event.block.timestamp;
  flow.txHash = event.transaction.hash;
  flow.save();

  const gameEpoch = loadGameEpoch(event.params.epoch, event.params.gameId);
  gameEpoch.volumeOut = gameEpoch.volumeOut.plus(event.params.amount);
  gameEpoch.flowCount = gameEpoch.flowCount.plus(BigInt.fromI32(1));
  gameEpoch.save();
}

export function handlePotFunded(event: PotFundedEvent): void {
  const gameEpoch = loadGameEpoch(event.params.epoch, event.params.gameId);
  gameEpoch.potFunded = gameEpoch.potFunded.plus(event.params.amount);
  gameEpoch.save();
}

export function handleSplitsSet(event: SplitsSetEvent): void {
  const config = loadConfig();
  config.globalBps = event.params.globalBps;
  config.projectBps = event.params.projectBps;
  config.nftBps = event.params.nftBps;
  config.potBps = event.params.potBps;
  config.save();
}

export function handleScoreSet(event: ScoreSetEvent): void {
  const config = loadConfig();
  config.score = event.params.score;
  config.save();
}
