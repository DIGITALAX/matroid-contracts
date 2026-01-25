import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address } from "@graphprotocol/graph-ts"
import { ProjectPoolCreated } from "../generated/schema"
import { ProjectPoolCreated as ProjectPoolCreatedEvent } from "../generated/StakingFactory/StakingFactory"
import { handleProjectPoolCreated } from "../src/staking-factory"
import { createProjectPoolCreatedEvent } from "./staking-factory-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let project = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let pool = Address.fromString("0x0000000000000000000000000000000000000001")
    let newProjectPoolCreatedEvent = createProjectPoolCreatedEvent(
      project,
      pool
    )
    handleProjectPoolCreated(newProjectPoolCreatedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("ProjectPoolCreated created and stored", () => {
    assert.entityCount("ProjectPoolCreated", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "ProjectPoolCreated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "project",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "ProjectPoolCreated",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "pool",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
