import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { ClaimableCleared } from "../generated/schema"
import { ClaimableCleared as ClaimableClearedEvent } from "../generated/Treasury/Treasury"
import { handleClaimableCleared } from "../src/treasury"
import { createClaimableClearedEvent } from "./treasury-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let epoch = BigInt.fromI32(234)
    let project = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newClaimableClearedEvent = createClaimableClearedEvent(epoch, project)
    handleClaimableCleared(newClaimableClearedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("ClaimableCleared created and stored", () => {
    assert.entityCount("ClaimableCleared", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "ClaimableCleared",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "epoch",
      "234"
    )
    assert.fieldEquals(
      "ClaimableCleared",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "project",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
