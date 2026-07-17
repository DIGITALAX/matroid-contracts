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

interface IKitRegistryView {
    function verifier() external view returns (address);
    function editVerifier() external view returns (address);
}

contract DeployGanda is Script {
    string constant GANDA_URI =
        "ipfs://QmR1bWr66SzrqVio3gQ67MZV8cufLJ81Kc9PSHzfMKwdU5";

    function _pick(address envVal, address fallbackVal) internal pure returns (address) {
        return envVal == address(0) ? fallbackVal : envVal;
    }

    function run() external {
        string memory allPath = string.concat(
            "./deployments/all.",
            vm.toString(block.chainid),
            ".json"
        );

        address matroidKit;
        address globalPool;
        address identityRoots;
        address actionVerifier;
        address ownerVerifier;

        if (vm.exists(allPath)) {
            string memory allJson = vm.readFile(allPath);
            matroidKit = vm.parseJsonAddress(allJson, ".matroidKit");
            globalPool = vm.parseJsonAddress(allJson, ".globalStakingPool");
            identityRoots = vm.parseJsonAddress(allJson, ".identityRegistry");
            address kitRegistry = vm.parseJsonAddress(allJson, ".kitRegistry");
            actionVerifier = IKitRegistryView(kitRegistry).verifier();
            ownerVerifier = IKitRegistryView(kitRegistry).editVerifier();
        }

        matroidKit = _pick(vm.envOr("MATROID_KIT", address(0)), matroidKit);
        globalPool = _pick(vm.envOr("GLOBAL_STAKING_POOL", address(0)), globalPool);
        identityRoots = _pick(vm.envOr("IDENTITY_ROOTS", address(0)), identityRoots);
        actionVerifier = _pick(vm.envOr("IDENTITY_ACTION_VERIFIER", address(0)), actionVerifier);
        ownerVerifier = _pick(vm.envOr("EDIT_VERIFIER", address(0)), ownerVerifier);

        require(matroidKit != address(0), "MATROID_KIT missing");
        require(globalPool != address(0), "GLOBAL_STAKING_POOL missing");
        require(identityRoots != address(0), "IDENTITY_ROOTS missing");
        require(actionVerifier != address(0), "IDENTITY_ACTION_VERIFIER missing");
        require(ownerVerifier != address(0), "EDIT_VERIFIER missing");

        string memory metadata = vm.envOr("GANDA_METADATA", string(GANDA_URI));
        uint16 globalBps = uint16(vm.envOr("GANDA_GLOBAL_BPS", uint256(2000)));
        uint16 projectBps = uint16(vm.envOr("GANDA_PROJECT_BPS", uint256(1000)));
        uint16 nftBps = uint16(vm.envOr("GANDA_NFT_BPS", uint256(0)));
        uint16 potBps = uint16(vm.envOr("GANDA_POT_BPS", uint256(1000)));
        uint16 gamesPotBps = uint16(vm.envOr("GANDA_GAMES_POT_BPS", uint256(6500)));
        uint256 claimWindow = vm.envOr("GANDA_CLAIM_WINDOW_EPOCHS", uint256(2));
        uint256 voteDuration = vm.envOr("GANDA_VOTE_DURATION", uint256(3 days));
        uint256 quorum = vm.envOr("GANDA_QUORUM", uint256(2));
        uint256 paymasterCap = vm.envOr("GANDA_PAYMASTER_CAP", uint256(100 ether));
        uint256 paymasterFund = vm.envOr("GANDA_PAYMASTER_FUND", uint256(10 ether));

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
        paymaster.setCoreTarget(identityRoots, true);
        paymaster.transferGovernance(address(council));
        council.setPaymaster(address(paymaster));
        if (paymasterFund > 0 && deployer.balance > paymasterFund) {
            paymaster.fund{value: paymasterFund}();
        }

        vm.stopBroadcast();

        string memory obj = "ganda";
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "accessControl", address(acl));
        vm.serializeAddress(obj, "blacklist", address(blacklist));
        vm.serializeAddress(obj, "games", address(games));
        vm.serializeAddress(obj, "hub", address(hub));
        vm.serializeAddress(obj, "score", address(score));
        vm.serializeAddress(obj, "council", address(council));
        vm.serializeAddress(obj, "identityRegistry", identityRoots);
        vm.serializeAddress(obj, "matroidKit", matroidKit);
        vm.serializeAddress(obj, "globalStakingPool", globalPool);
        string memory out = vm.serializeAddress(
            obj,
            "paymaster",
            address(paymaster)
        );
        vm.writeJson(
            out,
            string.concat(
                "./deployments/ganda.",
                vm.toString(block.chainid),
                ".json"
            )
        );

        console.log("GandaAccessControl:", address(acl));
        console.log("GandaBlacklist:", address(blacklist));
        console.log("GandaGames:", address(games));
        console.log("GandaHub:", address(hub));
        console.log("GandaScore:", address(score));
        console.log("GandaCouncil:", address(council));
        console.log("GandaPaymaster:", address(paymaster));
    }
}
