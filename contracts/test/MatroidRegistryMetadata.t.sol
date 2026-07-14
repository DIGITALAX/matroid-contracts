// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {StakingFactory} from "../src/StakingFactory.sol";
import {TestMona} from "../src/zk/testing/TestMona.sol";
import {TestProject} from "./TestProject.sol";
import "../src/MatroidErrors.sol";

contract MatroidRegistryMetadataTest is Test {
    MatroidRegistry registry;
    MatroidKit kit;
    TestMona mona;
    TestProject project;

    function setUp() public {
        mona = new TestMona();
        StakingFactory factory = new StakingFactory(7 days);
        registry = new MatroidRegistry(
            address(mona),
            address(factory),
            7 days,
            100,
            1000 ether
        );
        kit = new MatroidKit(address(registry));
        registry.setMatroidKit(address(kit));
        project = new TestProject(address(mona), address(kit));
        project.register("ipfs://old", false);
    }

    function testUpdateMetadata() public {
        project.updateMetadata("ipfs://new");
        assertEq(registry.getProject(address(project)).metadata, "ipfs://new");
    }

    function testUpdateMetadataEmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit MatroidRegistry.ProjectMetadataUpdated(address(project), "ipfs://again");
        project.updateMetadata("ipfs://again");
    }

    function testUpdateMetadataNotRegisteredReverts() public {
        vm.expectRevert(MatroidErrors.ProjectNotRegistered.selector);
        registry.updateMetadata("ipfs://x");
    }

    function testUpdateMetadataOnlyOwnerOnProject() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(TestProject.NotOwner.selector);
        project.updateMetadata("ipfs://nope");
    }

    function testUpdateMetadataAfterLeaveReverts() public {
        vm.prank(address(project));
        registry.leave();
        vm.prank(address(project));
        vm.expectRevert(MatroidErrors.ProjectNotRegistered.selector);
        registry.updateMetadata("ipfs://gone");
    }
}
