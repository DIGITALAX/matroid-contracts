// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {GandaAccessControl} from "../src/Ganda/GandaAccessControl.sol";
import {GandaBlacklist} from "../src/Ganda/GandaBlacklist.sol";
import {GandaGames} from "../src/Ganda/GandaGames.sol";
import {GandaHub} from "../src/Ganda/GandaHub.sol";
import {GandaScore} from "../src/Ganda/GandaScore.sol";
import {GandaCouncil} from "../src/Ganda/GandaCouncil.sol";
import {GandaPaymaster} from "../src/Ganda/GandaPaymaster.sol";

contract DeployGanda is Script {
    string constant GANDA_URI =
        "ipfs://QmR1bWr66SzrqVio3gQ67MZV8cufLJ81Kc9PSHzfMKwdU5";

    function run() external {
        address matroidKit = vm.envAddress("MATROID_KIT");
        address globalPool = vm.envAddress("GLOBAL_STAKING_POOL");
        address actionVerifier = vm.envAddress("IDENTITY_ACTION_VERIFIER");
        address ownerVerifier = vm.envAddress("EDIT_VERIFIER");
        address identityRoots = vm.envAddress("IDENTITY_ROOTS");

        string memory metadata = vm.envOr("GANDA_METADATA", string(GANDA_URI));
        uint16 globalBps = uint16(vm.envOr("GANDA_GLOBAL_BPS", uint256(2000)));
        uint16 projectBps = uint16(vm.envOr("GANDA_PROJECT_BPS", uint256(1000)));
        uint16 nftBps = uint16(vm.envOr("GANDA_NFT_BPS", uint256(0)));
        uint16 potBps = uint16(vm.envOr("GANDA_POT_BPS", uint256(1000)));
        uint16 gamesPotBps = uint16(vm.envOr("GANDA_GAMES_POT_BPS", uint256(6500)));
        uint256 claimWindow = vm.envOr("GANDA_CLAIM_WINDOW_EPOCHS", uint256(2));
        uint256 voteDuration = vm.envOr("GANDA_VOTE_DURATION", uint256(3 days));
        uint256 quorum = vm.envOr("GANDA_QUORUM", uint256(2));
        uint256 paymasterCap = vm.envOr("GANDA_PAYMASTER_CAP", uint256(1 ether));
        uint256 paymasterFund = vm.envOr("GANDA_PAYMASTER_FUND", uint256(0));

        vm.startBroadcast();
        address deployer = msg.sender;

        GandaAccessControl acl = new GandaAccessControl();
        GandaBlacklist blacklist = new GandaBlacklist(address(acl));
        GandaGames games = new GandaGames(
            actionVerifier,
            identityRoots,
            ownerVerifier,
            address(acl),
            address(blacklist)
        );
        GandaHub hub = new GandaHub(
            address(acl),
            address(games),
            matroidKit,
            globalPool
        );
        GandaScore score = new GandaScore(
            actionVerifier,
            identityRoots,
            ownerVerifier,
            address(acl),
            address(blacklist),
            address(games),
            address(hub),
            gamesPotBps,
            claimWindow
        );
        hub.setScore(address(score));
        hub.bootstrap(metadata, globalBps, projectBps, nftBps, potBps);

        GandaCouncil council = new GandaCouncil(
            actionVerifier,
            identityRoots,
            address(acl),
            address(blacklist),
            address(games),
            address(hub),
            address(score),
            voteDuration,
            quorum
        );
        acl.addAdmin(address(council));
        blacklist.setSetter(address(council), true);

        GandaPaymaster paymaster = new GandaPaymaster(
            address(games),
            deployer,
            paymasterCap
        );
        paymaster.setCoreTarget(address(games), true);
        paymaster.setCoreTarget(address(score), true);
        paymaster.setCoreTarget(address(council), true);
        paymaster.transferGovernance(address(council));
        council.setPaymaster(address(paymaster));
        if (paymasterFund > 0) {
            paymaster.fund{value: paymasterFund}();
        }

        vm.stopBroadcast();

        console.log("GandaAccessControl:", address(acl));
        console.log("GandaBlacklist:", address(blacklist));
        console.log("GandaGames:", address(games));
        console.log("GandaHub:", address(hub));
        console.log("GandaScore:", address(score));
        console.log("GandaCouncil:", address(council));
        console.log("GandaPaymaster:", address(paymaster));
    }
}
