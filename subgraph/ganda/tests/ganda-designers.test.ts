import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { DesignerDeactivated } from "../generated/schema"
import { DesignerDeactivated as DesignerDeactivatedEvent } from "../generated/GandaDesigners/GandaDesigners"
import { handleDesignerDeactivated } from "../src/ganda-designers"
import { createDesignerDeactivatedEvent } from "./ganda-designers-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let designerId = BigInt.fromI32(234)
    let inviter = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newDesignerDeactivatedEvent = createDesignerDeactivatedEvent(
      designerId,
      inviter
    )
    handleDesignerDeactivated(newDesignerDeactivatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("DesignerDeactivated created and stored", () => {
    assert.entityCount("DesignerDeactivated", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "DesignerDeactivated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "designerId",
      "234"
    )
    assert.fieldEquals(
      "DesignerDeactivated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "inviter",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
