import { Banned as BannedEvent } from "../generated/Blacklist/Blacklist";
import { CreatorBan } from "../generated/schema";

export function handleBanned(event: BannedEvent): void {
  let id =
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let ban = new CreatorBan(id);
  ban.creator = event.params.who;
  ban.actor = event.params.by;
  ban.banned = event.params.banned;
  ban.createdAtTimestamp = event.block.timestamp;
  ban.transactionHash = event.transaction.hash;
  ban.save();
}
