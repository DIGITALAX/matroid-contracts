// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {ContentRegistry} from "../src/zk/ContentRegistry.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {Blacklist} from "../src/zk/Blacklist.sol";

contract DeployZk is Script {
    function run() external {
        address poseidon = vm.envAddress("POSEIDON");
        address enrollmentVerifier = vm.envAddress("ENROLLMENT_VERIFIER");
        address editVerifier = vm.envAddress("EDIT_VERIFIER");
        address actionVerifier = vm.envAddress("IDENTITY_ACTION_VERIFIER");

        vm.startBroadcast();

        IdentityRegistry identity = new IdentityRegistry(enrollmentVerifier, poseidon);

        Blacklist blacklist = new Blacklist(msg.sender);
        ContentRegistry content = new ContentRegistry(editVerifier, actionVerifier, address(identity), address(blacklist));
        KitSignal kitSignal = new KitSignal(actionVerifier, address(identity));

        vm.stopBroadcast();

        content;
        kitSignal;
    }
}
