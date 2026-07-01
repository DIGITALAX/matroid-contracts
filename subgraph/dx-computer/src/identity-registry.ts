import { Enrolled as EnrolledEvent } from "../generated/IdentityRegistry/IdentityRegistry";
import { Enrollment, _EnrollmentCounter } from "../generated/schema";

export function handleEnrolled(event: EnrolledEvent): void {
  let counter = _EnrollmentCounter.load("global");
  if (counter == null) {
    counter = new _EnrollmentCounter("global");
    counter.count = 0;
  }
  let index = counter.count;
  counter.count = index + 1;
  counter.save();

  let e = new Enrollment(event.params.identityCommitment.toString());
  e.commitment = event.params.identityCommitment;
  e.leafIndex = index;
  e.createdAtBlock = event.block.number;
  e.createdAtTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
