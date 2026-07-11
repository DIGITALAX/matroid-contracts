import { Bytes } from "@graphprotocol/graph-ts";
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

  let commitmentHex = event.params.identityCommitment.toHexString().slice(2);
  if (commitmentHex.length % 2 == 1) {
    commitmentHex = "0" + commitmentHex;
  }
  let id = Bytes.fromHexString("0x" + commitmentHex);
  let e = new Enrollment(id);
  e.commitment = event.params.identityCommitment;
  e.leafIndex = index;
  e.blockNumber = event.block.number;
  e.blockTimestamp = event.block.timestamp;
  e.transactionHash = event.transaction.hash;
  e.save();
}
