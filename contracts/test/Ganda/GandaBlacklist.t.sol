// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";

contract GandaBlacklistTest is GandaTestBase {
    function testAdminCanBan() public {
        blacklist.setGameBan(1, true);
        assertTrue(blacklist.isGameBanned(1));
        blacklist.setGameBan(1, false);
        assertFalse(blacklist.isGameBanned(1));
    }

    function testTagBan() public {
        blacklist.setTagBan(ownerTag, true);
        assertTrue(blacklist.isTagBanned(ownerTag));
    }

    function testNonSetterReverts() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        blacklist.setGameBan(1, true);
    }

    function testSetterCanBan() public {
        blacklist.setSetter(player, true);
        vm.prank(player);
        blacklist.setGameBan(2, true);
        assertTrue(blacklist.isGameBanned(2));
    }

    function testOnlyAdminSetsSetter() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        blacklist.setSetter(player, true);
    }
}
