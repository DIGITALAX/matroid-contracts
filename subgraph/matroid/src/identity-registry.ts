import { Bytes } from "@graphprotocol/graph-ts";
import { Enrolled as EnrolledEvent } from "../generated/IdentityRegistry/IdentityRegistry";
import { Enrollment } from "../generated/schema";

export function handleEnrolled(event: EnrolledEvent): void {
  let commitmentHex = event.params.commitment.toHexString().slice(2);
  if (commitmentHex.length % 2 == 1) {
    commitmentHex = "0" + commitmentHex;
  }
  let id = Bytes.fromHexString("0x" + commitmentHex);
  let e = new Enrollment(id);
  e.commitment = event.params.commitment;
  e.leafIndex = event.params.leafIndex.toI32();
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
