import { BigInt, Bytes } from "@graphprotocol/graph-ts";
import {
  GamePublished as GamePublishedEvent,
  GameVersioned as GameVersionedEvent,
  GameRetagged as GameRetaggedEvent,
  GameRemoved as GameRemovedEvent,
  GameErased as GameErasedEvent,
  GameAdminEdited as GameAdminEditedEvent,
} from "../generated/GandaGames/GandaGames";
import { Game, GameVersion } from "../generated/schema";

export function handleGamePublished(event: GamePublishedEvent): void {
  const id = event.params.gameId.toString();
  const game = new Game(id);
  game.gameId = event.params.gameId;
  game.ownerTag = event.params.ownerTag;
  game.scorer = event.params.scorer;
  game.uri = event.params.uri;
  game.version = BigInt.zero();
  game.publishedAt = event.block.timestamp;
  game.removed = false;
  game.removedByAdmin = false;
  game.erased = false;
  game.banned = false;
  game.save();

  const version = new GameVersion(id + "-0");
  version.game = id;
  version.scorer = event.params.scorer;
  version.version = BigInt.zero();
  version.uri = event.params.uri;
  version.timestamp = event.block.timestamp;
  version.save();
}

export function handleGameVersioned(event: GameVersionedEvent): void {
  const id = event.params.gameId.toString();
  const game = Game.load(id);
  if (game == null) return;
  game.scorer = event.params.scorer;
  game.uri = event.params.uri;
  game.version = BigInt.fromU64(event.params.version);
  game.save();

  const version = new GameVersion(id + "-" + event.params.version.toString());
  version.game = id;
  version.scorer = event.params.scorer;
  version.version = BigInt.fromU64(event.params.version);
  version.uri = event.params.uri;
  version.timestamp = event.block.timestamp;
  version.save();
}

export function handleGameRetagged(event: GameRetaggedEvent): void {
  const game = Game.load(event.params.gameId.toString());
  if (game == null) return;
  game.ownerTag = event.params.newOwnerTag;
  game.save();
}

export function handleGameRemoved(event: GameRemovedEvent): void {
  const game = Game.load(event.params.gameId.toString());
  if (game == null) return;
  game.removed = true;
  game.removedByAdmin = event.params.byAdmin;
  game.save();
}

export function handleGameErased(event: GameErasedEvent): void {
  const game = Game.load(event.params.gameId.toString());
  if (game == null) return;
  game.erased = true;
  game.removed = true;
  game.uri = "";
  game.ownerTag = Bytes.empty();
  game.scorer = Bytes.empty();
  game.save();
}

export function handleGameAdminEdited(event: GameAdminEditedEvent): void {
  const game = Game.load(event.params.gameId.toString());
  if (game == null) return;
  game.uri = event.params.uri;
  game.save();
}
