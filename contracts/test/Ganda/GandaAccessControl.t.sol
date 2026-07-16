// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";

contract GandaAccessControlTest is GandaTestBase {
    function testDeployerIsAdmin() public view {
        assertTrue(acl.isAdmin(address(this)));
    }

    function testAddRemoveAdmin() public {
        acl.addAdmin(player);
        assertTrue(acl.isAdmin(player));
        acl.removeAdmin(player);
        assertFalse(acl.isAdmin(player));
    }

    function testCannotRemoveSelf() public {
        vm.expectRevert(GandaErrors.InvalidInput.selector);
        acl.removeAdmin(address(this));
    }

    function testNonAdminCannotAdd() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        acl.addAdmin(player2);
    }
}
