// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreVerifier} from "@semaphore-protocol/contracts/interfaces/ISemaphoreVerifier.sol";
import {Semaphore} from "@semaphore-protocol/contracts/Semaphore.sol";
import {SemaphoreVerifier} from "@semaphore-protocol/contracts/base/SemaphoreVerifier.sol";
import {KitRegistry} from "../src/zk/KitRegistry.sol";
import {GrantRegistry} from "../src/zk/GrantRegistry.sol";
import {PrefabMarket} from "../src/zk/PrefabMarket.sol";
import {CyberswagmanRegistry} from "../src/zk/CyberswagmanRegistry.sol";
import {SponsorVault} from "../src/zk/SponsorVault.sol";
import {ContentRegistry} from "../src/zk/ContentRegistry.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {Blacklist} from "../src/zk/Blacklist.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {DxCouncil} from "../src/zk/DxCouncil.sol";
import {TestSnapshotSource} from "../src/zk/testing/TestSnapshotSource.sol";
import {AlwaysTrueVerifier} from "../src/zk/testing/AlwaysTrueVerifier.sol";
import {AlwaysTrueRoots} from "../src/zk/testing/AlwaysTrueRoots.sol";
import {TestGasPool} from "../src/zk/testing/TestGasPool.sol";
import {TestTreasurySink} from "../src/zk/testing/TestTreasurySink.sol";
import {TestMona} from "../src/zk/testing/TestMona.sol";

/// First-pass anvil deploy: everything needed to test dx.computer's PUBLIC
/// (no-chip) paths. Anonymous paths (enroll, signal, post-anon, vote) are wired
/// with test-only stand-ins (AlwaysTrueVerifier/AlwaysTrueRoots) so the contracts
/// deploy and the public functions work, but the anonymous functions are NOT yet
/// backed by real proofs — that needs MonaBalanceTree/SponsorCouncil, a real
/// Poseidon hasher contract, and the real voting/edit verifier contracts, none of
/// which exist yet. This script deliberately does not deploy those two.
contract DeployPublic is Script {
    function run() external {
        vm.startBroadcast();

        SemaphoreVerifier semaphoreVerifier = new SemaphoreVerifier();
        Semaphore semaphoreContract = new Semaphore(ISemaphoreVerifier(address(semaphoreVerifier)));
        address semaphore = address(semaphoreContract);

        TestMona mona = new TestMona();
        AlwaysTrueVerifier verifier = new AlwaysTrueVerifier();
        AlwaysTrueRoots roots = new AlwaysTrueRoots();
        TestGasPool gasPool = new TestGasPool();

        IdentityRegistry identity = new IdentityRegistry(address(verifier), semaphore);
        uint256 groupId = identity.groupId();

        Blacklist blacklist = new Blacklist(msg.sender);

        TestSnapshotSource snapshots = new TestSnapshotSource();
        DxCouncil council = new DxCouncil(
            address(verifier),
            semaphore,
            groupId,
            address(snapshots),
            address(blacklist),
            0,
            5 minutes,
            1,
            1
        );

        KitRegistry kitRegistry = new KitRegistry(address(verifier), address(verifier), address(roots), address(blacklist));
        GrantRegistry grantRegistry = new GrantRegistry(address(mona), address(blacklist));
        CyberswagmanRegistry cyberRegistry = new CyberswagmanRegistry(address(blacklist));
        SponsorVault sponsorVault = new SponsorVault(address(gasPool), address(mona));
        TestTreasurySink treasury = new TestTreasurySink(address(mona));
        PrefabMarket market = new PrefabMarket(
            address(mona),
            address(sponsorVault),
            address(treasury),
            address(grantRegistry),
            address(cyberRegistry),
            500,
            0,
            address(blacklist),
            address(0)
        );
        ContentRegistry content = new ContentRegistry(address(verifier), semaphore, groupId, address(blacklist));
        KitSignal kitSignal = new KitSignal(semaphore, groupId);

        // ban writers: dx.app's own council + the rugged-creator path in GrantRegistry
        blacklist.setSetter(address(council), true);
        blacklist.setSetter(address(grantRegistry), true);

        vm.stopBroadcast();

        console.log("Semaphore:", semaphore);
        console.log("TestMona:", address(mona));
        console.log("KitRegistry:", address(kitRegistry));
        console.log("GrantRegistry:", address(grantRegistry));
        console.log("CyberswagmanRegistry:", address(cyberRegistry));
        console.log("SponsorVault:", address(sponsorVault));
        console.log("PrefabMarket:", address(market));
        console.log("ContentRegistry:", address(content));
        console.log("KitSignal:", address(kitSignal));
        console.log("IdentityRegistry:", address(identity));
        console.log("DxCouncil:", address(council));
        console.log("Semaphore groupId:", groupId);

        string memory json = "public-deploy";
        vm.serializeAddress(json, "semaphore", semaphore);
        vm.serializeAddress(json, "semaphoreVerifier", address(semaphoreVerifier));
        vm.serializeUint(json, "groupId", groupId);
        vm.serializeAddress(json, "mona", address(mona));
        vm.serializeAddress(json, "kitRegistry", address(kitRegistry));
        vm.serializeAddress(json, "grantRegistry", address(grantRegistry));
        vm.serializeAddress(json, "cyberswagmanRegistry", address(cyberRegistry));
        vm.serializeAddress(json, "sponsorVault", address(sponsorVault));
        vm.serializeAddress(json, "prefabMarket", address(market));
        vm.serializeAddress(json, "contentRegistry", address(content));
        vm.serializeAddress(json, "blacklist", address(blacklist));
        vm.serializeAddress(json, "identityRegistry", address(identity));
        vm.serializeAddress(json, "dxCouncil", address(council));
        string memory finalJson = vm.serializeAddress(json, "kitSignal", address(kitSignal));
        vm.writeJson(finalJson, "./deployments/public.anvil.json");
    }
}
