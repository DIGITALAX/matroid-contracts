import { BigInt } from "@graphprotocol/graph-ts";
import {
  ScoreSubmitted as ScoreSubmittedEvent,
  PotNotified as PotNotifiedEvent,
  PlayerClaimed as PlayerClaimedEvent,
  GamePotClaimed as GamePotClaimedEvent,
  PlayerErased as PlayerErasedEvent,
  ExpiredRolled as ExpiredRolledEvent,
  ParamsSet as ParamsSetEvent,
} from "../generated/GandaScore/GandaScore";
import {
  ScoreSubmission,
  PlayerEpochGame,
  PlayerEpoch,
  Pot,
  PotClaim,
  GameEpoch,
  GandaConfig,
} from "../generated/schema";

function loadPot(epoch: BigInt): Pot {
  let pot = Pot.load(epoch.toString());
  if (pot == null) {
    pot = new Pot(epoch.toString());
    pot.epoch = epoch;
    pot.funded = BigInt.zero();
    pot.playerClaimed = BigInt.zero();
    pot.gameClaimed = BigInt.zero();
    pot.rolledOut = BigInt.zero();
    pot.rolledIn = BigInt.zero();
  }
  return pot;
}

function playerEpochId(epoch: BigInt, playerKey: string): string {
  return epoch.toString() + "-" + playerKey;
}

export function handleScoreSubmitted(event: ScoreSubmittedEvent): void {
  const gameId = event.params.gameId.toString();
  const playerKeyHex = event.params.playerKey.toHexString();

  const submission = new ScoreSubmission(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  submission.game = gameId;
  submission.epoch = event.params.epoch;
  submission.playerKey = event.params.playerKey;
  submission.points = event.params.points;
  submission.anonymous = event.params.anon;
  submission.timestamp = event.block.timestamp;
  submission.save();

  const pegId =
    event.params.epoch.toString() + "-" + gameId + "-" + playerKeyHex;
  let peg = PlayerEpochGame.load(pegId);
  const isNew = peg == null;
  if (peg == null) {
    peg = new PlayerEpochGame(pegId);
    peg.epoch = event.params.epoch;
    peg.game = gameId;
    peg.playerKey = event.params.playerKey;
    peg.points = BigInt.zero();
  }
  peg.points = peg.points.plus(event.params.points);
  peg.save();

  const peId = playerEpochId(event.params.epoch, playerKeyHex);
  let playerEpoch = PlayerEpoch.load(peId);
  if (playerEpoch == null) {
    playerEpoch = new PlayerEpoch(peId);
    playerEpoch.epoch = event.params.epoch;
    playerEpoch.playerKey = event.params.playerKey;
    playerEpoch.gameIds = [];
    playerEpoch.playerEpochGameIds = [];
    playerEpoch.erased = false;
    playerEpoch.claimed = false;
    playerEpoch.claimAmount = BigInt.zero();
  }
  if (isNew) {
    const gameIds = playerEpoch.gameIds;
    gameIds.push(gameId);
    playerEpoch.gameIds = gameIds;
    const pegIds = playerEpoch.playerEpochGameIds;
    pegIds.push(pegId);
    playerEpoch.playerEpochGameIds = pegIds;
  }
  playerEpoch.erased = false;
  playerEpoch.save();

  const geId = event.params.epoch.toString() + "-" + gameId;
  let gameEpoch = GameEpoch.load(geId);
  if (gameEpoch == null) {
    gameEpoch = new GameEpoch(geId);
    gameEpoch.game = gameId;
    gameEpoch.epoch = event.params.epoch;
    gameEpoch.volumeIn = BigInt.zero();
    gameEpoch.volumeOut = BigInt.zero();
    gameEpoch.flowCount = BigInt.zero();
    gameEpoch.potFunded = BigInt.zero();
    gameEpoch.totalPoints = BigInt.zero();
    gameEpoch.playerCount = BigInt.zero();
    gameEpoch.potClaimed = false;
    gameEpoch.potClaimAmount = BigInt.zero();
  }
  gameEpoch.totalPoints = gameEpoch.totalPoints.plus(event.params.points);
  if (isNew) {
    gameEpoch.playerCount = gameEpoch.playerCount.plus(BigInt.fromI32(1));
  }
  gameEpoch.save();
}

export function handlePotNotified(event: PotNotifiedEvent): void {
  const pot = loadPot(event.params.epoch);
  pot.funded = pot.funded.plus(event.params.amount);
  pot.save();
}

export function handlePlayerClaimed(event: PlayerClaimedEvent): void {
  const playerKeyHex = event.params.playerKey.toHexString();
  const claim = new PotClaim(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  claim.epoch = event.params.epoch;
  claim.kind = "player";
  claim.playerKey = event.params.playerKey;
  claim.payout = event.params.payout;
  claim.amount = event.params.amount;
  claim.timestamp = event.block.timestamp;
  claim.save();

  const pot = loadPot(event.params.epoch);
  pot.playerClaimed = pot.playerClaimed.plus(event.params.amount);
  pot.save();

  const playerEpoch = PlayerEpoch.load(
    playerEpochId(event.params.epoch, playerKeyHex),
  );
  if (playerEpoch != null) {
    playerEpoch.claimed = true;
    playerEpoch.claimPayout = event.params.payout;
    playerEpoch.claimAmount = event.params.amount;
    playerEpoch.save();
  }
}

export function handleGamePotClaimed(event: GamePotClaimedEvent): void {
  const gameId = event.params.gameId.toString();
  const claim = new PotClaim(
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString(),
  );
  claim.epoch = event.params.epoch;
  claim.kind = "game";
  claim.game = gameId;
  claim.payout = event.params.payout;
  claim.amount = event.params.amount;
  claim.timestamp = event.block.timestamp;
  claim.save();

  const pot = loadPot(event.params.epoch);
  pot.gameClaimed = pot.gameClaimed.plus(event.params.amount);
  pot.save();

  const gameEpoch = GameEpoch.load(
    event.params.epoch.toString() + "-" + gameId,
  );
  if (gameEpoch != null) {
    gameEpoch.potClaimed = true;
    gameEpoch.potClaimAmount = event.params.amount;
    gameEpoch.save();
  }
}

export function handlePlayerErased(event: PlayerErasedEvent): void {
  const playerKeyHex = event.params.playerKey.toHexString();
  const playerEpoch = PlayerEpoch.load(
    playerEpochId(event.params.epoch, playerKeyHex),
  );
  if (playerEpoch == null) return;
  playerEpoch.erased = true;
  const pegIds = playerEpoch.playerEpochGameIds;
  for (let i = 0; i < pegIds.length; i++) {
    const peg = PlayerEpochGame.load(pegIds[i]);
    if (peg != null) {
      const gameEpoch = GameEpoch.load(
        event.params.epoch.toString() + "-" + peg.game,
      );
      if (gameEpoch != null) {
        gameEpoch.totalPoints = gameEpoch.totalPoints.minus(peg.points);
        gameEpoch.playerCount = gameEpoch.playerCount.minus(BigInt.fromI32(1));
        gameEpoch.save();
      }
      peg.points = BigInt.zero();
      peg.save();
    }
  }
  playerEpoch.gameIds = [];
  playerEpoch.playerEpochGameIds = [];
  playerEpoch.save();
}

export function handleExpiredRolled(event: ExpiredRolledEvent): void {
  const from = loadPot(event.params.fromEpoch);
  from.rolledOut = from.rolledOut.plus(event.params.amount);
  from.save();
  const to = loadPot(event.params.toEpoch);
  to.rolledIn = to.rolledIn.plus(event.params.amount);
  to.funded = to.funded.plus(event.params.amount);
  to.save();
}

export function handleParamsSet(event: ParamsSetEvent): void {
  let config = GandaConfig.load("ganda");
  if (config == null) {
    config = new GandaConfig("ganda");
    config.metadata = "";
    config.globalBps = 0;
    config.projectBps = 0;
    config.nftBps = 0;
    config.potBps = 0;
    config.paymasterDefaultCap = BigInt.zero();
  }
  config.gamesPotBps = event.params.gamesPotBps;
  config.claimWindowEpochs = event.params.claimWindowEpochs;
  config.save();
}
