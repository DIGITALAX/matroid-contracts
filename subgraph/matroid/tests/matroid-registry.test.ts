import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import { ClaimerUpdated } from "../generated/schema"
import { ClaimerUpdated as ClaimerUpdatedEvent } from "../generated/MatroidRegistry/MatroidRegistry"
import { handleClaimerUpdated } from "../src/matroid-registry"
import { createClaimerUpdatedEvent } from "./matroid-registry-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let project = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let claimer = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let allowed = "boolean Not implemented"
    let newClaimerUpdatedEvent = createClaimerUpdatedEvent(
      project,
      claimer,
      allowed
    )
    handleClaimerUpdated(newClaimerUpdatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("ClaimerUpdated created and stored", () => {
    assert.entityCount("ClaimerUpdated", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "ClaimerUpdated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "project",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "ClaimerUpdated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "claimer",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "ClaimerUpdated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "allowed",
      "boolean Not implemented"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
