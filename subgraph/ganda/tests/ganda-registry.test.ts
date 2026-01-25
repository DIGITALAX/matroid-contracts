import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { GandaDeactivated } from "../generated/schema"
import { GandaDeactivated as GandaDeactivatedEvent } from "../generated/GandaRegistry/GandaRegistry"
import { handleGandaDeactivated } from "../src/ganda-registry"
import { createGandaDeactivatedEvent } from "./ganda-registry-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let ganadaId = BigInt.fromI32(234)
    let newGandaDeactivatedEvent = createGandaDeactivatedEvent(ganadaId)
    handleGandaDeactivated(newGandaDeactivatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("GandaDeactivated created and stored", () => {
    assert.entityCount("GandaDeactivated", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "GandaDeactivated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "ganadaId",
      "234"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
