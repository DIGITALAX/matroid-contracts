// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {TestMona} from "../src/zk/testing/TestMona.sol";
import {AlwaysTrueVerifier} from "../src/zk/testing/AlwaysTrueVerifier.sol";
import {StakingFactory} from "../src/StakingFactory.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {GlobalStakingPool} from "../src/GlobalStakingPool.sol";
import {GandaAccessControl} from "../src/Ganda/GandaAccessControl.sol";
import {GandaBlacklist} from "../src/Ganda/GandaBlacklist.sol";
import {GandaGames} from "../src/Ganda/GandaGames.sol";
import {GandaHub} from "../src/Ganda/GandaHub.sol";
import {GandaScore} from "../src/Ganda/GandaScore.sol";
import {GandaCouncil} from "../src/Ganda/GandaCouncil.sol";
import {GandaPaymaster} from "../src/Ganda/GandaPaymaster.sol";

contract LocalRoots {
    function isKnownRoot(bytes32) external pure returns (bool) {
        return true;
    }
}

contract DeployGandaLocal is Script {
    function run() external {
        vm.startBroadcast();

        TestMona mona = new TestMona();
        StakingFactory factory = new StakingFactory(1 days);
        MatroidRegistry registry = new MatroidRegistry(
            address(mona),
            address(factory),
            1 weeks,
            10,
            1_000e18
        );
        MatroidKit kit = new MatroidKit(address(registry));
        registry.setMatroidKit(address(kit));
        GlobalStakingPool globalPool = new GlobalStakingPool(address(mona), 1 days);
        AlwaysTrueVerifier verifier = new AlwaysTrueVerifier();
        LocalRoots roots = new LocalRoots();
        kit.setVerification(address(verifier), address(roots));

        GandaAccessControl acl = new GandaAccessControl();
        GandaBlacklist blacklist = new GandaBlacklist(address(acl));
        GandaGames games = new GandaGames(
            address(verifier),
            address(roots),
            address(verifier),
            address(acl),
            address(blacklist)
        );
        GandaHub hub = new GandaHub(
            address(acl),
            address(games),
            address(kit),
            address(globalPool)
        );
        GandaScore score = new GandaScore(
            address(verifier),
            address(roots),
            address(verifier),
            address(acl),
            address(blacklist),
            address(games),
            address(hub),
            6500,
            2
        );
        hub.setScore(address(score));
        hub.bootstrap(
            "ipfs://QmR1bWr66SzrqVio3gQ67MZV8cufLJ81Kc9PSHzfMKwdU5",
            2000,
            1000,
            0,
            1000
        );

        GandaCouncil council = new GandaCouncil(
            address(verifier),
            address(roots),
            address(acl),
            address(blacklist),
            address(games),
            address(hub),
            address(score),
            3 days,
            2
        );
        acl.addAdmin(address(council));
        blacklist.setSetter(address(council), true);

        GandaPaymaster paymaster = new GandaPaymaster(
            address(games),
            msg.sender,
            1 ether
        );
        paymaster.setCoreTarget(address(games), true);
        paymaster.setCoreTarget(address(score), true);
        paymaster.setCoreTarget(address(council), true);
        paymaster.transferGovernance(address(council));
        council.setPaymaster(address(paymaster));
        paymaster.fund{value: 1 ether}();

        vm.stopBroadcast();

        console.log("MONA:", address(mona));
        console.log("MatroidRegistry:", address(registry));
        console.log("MatroidKit:", address(kit));
        console.log("GlobalStakingPool:", address(globalPool));
        console.log("Verifier(AlwaysTrue):", address(verifier));
        console.log("Roots(Local):", address(roots));
        console.log("GandaAccessControl:", address(acl));
        console.log("GandaBlacklist:", address(blacklist));
        console.log("GandaGames:", address(games));
        console.log("GandaHub:", address(hub));
        console.log("GandaScore:", address(score));
        console.log("GandaCouncil:", address(council));
        console.log("GandaPaymaster:", address(paymaster));
    }
}
