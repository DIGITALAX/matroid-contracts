// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {MonaBalanceTree} from "../src/zk/MonaBalanceTree.sol";
import {Ballot} from "../src/zk/Ballot.sol";
import {ContentRegistry} from "../src/zk/ContentRegistry.sol";

contract DeployZk is Script {
    function run() external {
        address mona = vm.envAddress("MONA");
        address poseidon = vm.envAddress("POSEIDON");
        address enrollmentVerifier = vm.envAddress("ENROLLMENT_VERIFIER");
        address votingVerifier = vm.envAddress("VOTING_VERIFIER");
        address commentVerifier = vm.envAddress("COMMENT_VERIFIER");
        address editVerifier = vm.envAddress("EDIT_VERIFIER");
        uint128 minBalance = uint128(vm.envUint("MIN_BALANCE"));

        vm.startBroadcast();

        IdentityRegistry identity = new IdentityRegistry(enrollmentVerifier, poseidon);
        MonaBalanceTree balances = new MonaBalanceTree(poseidon, mona);
        Ballot ballot = new Ballot(votingVerifier, address(identity), address(balances), minBalance);
        ContentRegistry content = new ContentRegistry(commentVerifier, editVerifier, address(identity));

        vm.stopBroadcast();

        ballot;
        content;
    }
}
