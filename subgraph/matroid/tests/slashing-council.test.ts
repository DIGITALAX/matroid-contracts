import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { BigInt, Address } from "@graphprotocol/graph-ts"
import { ProposalExecuted } from "../generated/schema"
import { ProposalExecuted as ProposalExecutedEvent } from "../generated/SlashingCouncil/SlashingCouncil"
import { handleProposalExecuted } from "../src/slashing-council"
import { createProposalExecutedEvent } from "./slashing-council-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let epoch = BigInt.fromI32(234)
    let project = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let slashBps = 123
    let blacklist = "boolean Not implemented"
    let newProposalExecutedEvent = createProposalExecutedEvent(
      epoch,
      project,
      slashBps,
      blacklist
    )
    handleProposalExecuted(newProposalExecutedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("ProposalExecuted created and stored", () => {
    assert.entityCount("ProposalExecuted", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "ProposalExecuted",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "epoch",
      "234"
    )
    assert.fieldEquals(
      "ProposalExecuted",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "project",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "ProposalExecuted",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "slashBps",
      "123"
    )
    assert.fieldEquals(
      "ProposalExecuted",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "blacklist",
      "boolean Not implemented"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
