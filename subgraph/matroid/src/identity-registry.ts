import { Enrolled as EnrolledEvent } from "../generated/IdentityRegistry/IdentityRegistry";
import { Enrollment } from "../generated/schema";

export function handleEnrolled(event: EnrolledEvent): void {
  let e = new Enrollment(event.params.commitment);
  e.commitment = event.params.commitment;
  e.leafIndex = event.params.leafIndex;
  e.root = event.params.root;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
