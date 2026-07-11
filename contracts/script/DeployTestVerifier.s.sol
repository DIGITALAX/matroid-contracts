// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {AlwaysTrueVerifier} from "../src/zk/testing/AlwaysTrueVerifier.sol";

/// Anvil/local-testing only. Deploys a stand-in ENROLLMENT_VERIFIER that accepts
/// any proof, so `enroll()` is callable without the real NXP chip. Never point
/// production at this contract's address.
contract DeployTestVerifier is Script {
    function run() external {
        vm.startBroadcast();
        AlwaysTrueVerifier verifier = new AlwaysTrueVerifier();
        vm.stopBroadcast();

        console.log("Test-only ENROLLMENT_VERIFIER deployed at:", address(verifier));
    }
}
