import {
  GameBanSet as GameBanSetEvent,
  TagBanSet as TagBanSetEvent,
  SetterChanged as SetterChangedEvent,
} from "../generated/GandaBlacklist/GandaBlacklist";
import { GameBan, TagBan, BlacklistSetter, Game } from "../generated/schema";

export function handleGameBanSet(event: GameBanSetEvent): void {
  const id = event.params.gameId.toString();
  let ban = GameBan.load(id);
  if (ban == null) {
    ban = new GameBan(id);
    ban.gameId = event.params.gameId;
  }
  ban.banned = event.params.banned;
  ban.by = event.params.by;
  ban.timestamp = event.block.timestamp;
  ban.save();

  const game = Game.load(id);
  if (game != null) {
    game.banned = event.params.banned;
    game.save();
  }
}

export function handleTagBanSet(event: TagBanSetEvent): void {
  const id = event.params.ownerTag.toHexString();
  let ban = TagBan.load(id);
  if (ban == null) {
    ban = new TagBan(id);
    ban.ownerTag = event.params.ownerTag;
  }
  ban.banned = event.params.banned;
  ban.by = event.params.by;
  ban.timestamp = event.block.timestamp;
  ban.save();
}

export function handleSetterChanged(event: SetterChangedEvent): void {
  const id = event.params.who.toHexString();
  let setter = BlacklistSetter.load(id);
  if (setter == null) {
    setter = new BlacklistSetter(id);
    setter.setter = event.params.who;
  }
  setter.allowed = event.params.allowed;
  setter.save();
}
