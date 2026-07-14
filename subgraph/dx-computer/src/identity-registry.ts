import { Enrolled as EnrolledEvent } from "../generated/IdentityRegistry/IdentityRegistry";
import { Enrollment } from "../generated/schema";

export function handleEnrolled(event: EnrolledEvent): void {
  let e = new Enrollment(event.params.commitment.toString());
  e.commitment = event.params.commitment;
  e.leafIndex = event.params.leafIndex.toI32();
  e.createdAtBlock = event.block.number;
  e.createdAtTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
