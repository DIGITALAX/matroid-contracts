// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {MonaBalanceTree} from "../src/zk/MonaBalanceTree.sol";
import {ContentRegistry} from "../src/zk/ContentRegistry.sol";
import {SponsorCouncil} from "../src/zk/SponsorCouncil.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {Blacklist} from "../src/zk/Blacklist.sol";

contract DeployZk is Script {
    function run() external {
        address mona = vm.envAddress("MONA");
        address poseidon = vm.envAddress("POSEIDON");
        address semaphore = vm.envAddress("SEMAPHORE");
        address enrollmentVerifier = vm.envAddress("ENROLLMENT_VERIFIER");
        address votingVerifier = vm.envAddress("VOTING_VERIFIER");
        address editVerifier = vm.envAddress("EDIT_VERIFIER");
        address paymaster = vm.envAddress("PAYMASTER");
        uint128 minBalance = uint128(vm.envUint("MIN_BALANCE"));
        uint64 votingWindow = uint64(vm.envUint("VOTING_WINDOW"));
        uint256 quorum = vm.envUint("QUORUM");
        uint256 quorumFloor = vm.envUint("QUORUM_FLOOR");

        vm.startBroadcast();

        IdentityRegistry identity = new IdentityRegistry(enrollmentVerifier, semaphore);
        uint256 groupId = identity.groupId();

        Blacklist blacklist = new Blacklist(msg.sender);
        MonaBalanceTree balances = new MonaBalanceTree(poseidon, mona, semaphore, groupId);
        ContentRegistry content = new ContentRegistry(editVerifier, semaphore, groupId, address(blacklist));
        KitSignal kitSignal = new KitSignal(semaphore, groupId);
        SponsorCouncil council = new SponsorCouncil(
            votingVerifier,
            semaphore,
            groupId,
            address(balances),
            paymaster,
            minBalance,
            votingWindow,
            quorum,
            quorumFloor
        );

        vm.stopBroadcast();

        content;
        kitSignal;
        council;
    }
}
