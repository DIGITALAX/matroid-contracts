// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";

contract GandaPaymasterTest is GandaTestBase {
    function testSetCoreTarget() public {
        paymaster.setCoreTarget(address(games), true);
        assertTrue(paymaster.coreTarget(address(games)));
        assertTrue(paymaster.targetRegistered(address(games)));
    }

    function testSetCoreTargetOnlyGovernance() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        paymaster.setCoreTarget(address(games), true);
    }

    function testRegisterGameTargetByScorer() public {
        uint256 id = publishGame();
        address gameContract = address(0x6A3E);
        vm.prank(scorer);
        paymaster.registerGameTarget(id, gameContract);
        assertTrue(paymaster.targetRegistered(gameContract));
        assertEq(paymaster.gameOfTarget(gameContract), id);
    }

    function testRegisterGameTargetNonScorerReverts() public {
        uint256 id = publishGame();
        vm.prank(player);
        vm.expectRevert(GandaErrors.NotScorer.selector);
        paymaster.registerGameTarget(id, address(0x6A3E));
    }

    function testRegisterBannedGameReverts() public {
        uint256 id = publishGame();
        blacklist.setGameBan(id, true);
        vm.prank(scorer);
        vm.expectRevert(GandaErrors.GameNotActive.selector);
        paymaster.registerGameTarget(id, address(0x6A3E));
    }

    function testUnregisterGameTarget() public {
        uint256 id = publishGame();
        address gameContract = address(0x6A3E);
        vm.prank(scorer);
        paymaster.registerGameTarget(id, gameContract);
        vm.prank(scorer);
        paymaster.unregisterGameTarget(gameContract);
        assertFalse(paymaster.targetRegistered(gameContract));
    }

    function testCapOfDefaultAndCustom() public {
        assertEq(paymaster.capOf(address(0x6A3E)), 1 ether);
        paymaster.setCap(address(0x6A3E), 3 ether);
        assertEq(paymaster.capOf(address(0x6A3E)), 3 ether);
    }

    function testTransferGovernance() public {
        paymaster.transferGovernance(player);
        vm.prank(player);
        paymaster.setDefaultCap(2 ether);
        assertEq(paymaster.defaultCapPerEpoch(), 2 ether);
    }

    function testFund() public {
        vm.deal(address(this), 5 ether);
        paymaster.fund{value: 2 ether}();
        assertEq(address(paymaster).balance, 2 ether);
    }
}
