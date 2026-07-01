import { Enrolled as EnrolledEvent } from "../generated/IdentityRegistry/IdentityRegistry";
import { Enrollment } from "../generated/schema";

export function handleEnrolled(event: EnrolledEvent): void {
  let e = new Enrollment(event.params.commitment.toHexString());
  e.commitment = event.params.commitment;
  e.leafIndex = event.params.leafIndex;
  e.root = event.params.root;
  e.createdAtBlock = event.block.number;
  e.createdAtTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
