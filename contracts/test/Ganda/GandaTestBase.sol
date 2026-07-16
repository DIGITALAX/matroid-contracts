// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TestMona} from "../../src/zk/testing/TestMona.sol";
import {AlwaysTrueVerifier} from "../../src/zk/testing/AlwaysTrueVerifier.sol";
import {StakingFactory} from "../../src/StakingFactory.sol";
import {MatroidRegistry} from "../../src/MatroidRegistry.sol";
import {MatroidKit} from "../../src/MatroidKit.sol";
import {GlobalStakingPool} from "../../src/GlobalStakingPool.sol";
import {GandaAccessControl} from "../../src/Ganda/GandaAccessControl.sol";
import {GandaBlacklist} from "../../src/Ganda/GandaBlacklist.sol";
import {GandaGames} from "../../src/Ganda/GandaGames.sol";
import {GandaHub} from "../../src/Ganda/GandaHub.sol";
import {GandaScore} from "../../src/Ganda/GandaScore.sol";
import {GandaCouncil} from "../../src/Ganda/GandaCouncil.sol";
import {GandaPaymaster} from "../../src/Ganda/GandaPaymaster.sol";

contract MockRoots {
    function isKnownRoot(bytes32) external pure returns (bool) {
        return true;
    }
}

contract GandaTestBase is Test {
    TestMona mona;
    StakingFactory factory;
    MatroidRegistry registry;
    MatroidKit kit;
    GlobalStakingPool globalPool;
    AlwaysTrueVerifier verifier;
    MockRoots roots;
    GandaAccessControl acl;
    GandaBlacklist blacklist;
    GandaGames games;
    GandaHub hub;
    GandaScore score;
    GandaCouncil council;
    GandaPaymaster paymaster;

    address scorer = address(0xBEEF);
    address scorer2 = address(0xBEE2);
    address player = address(0xCAFE);
    address player2 = address(0xCAF2);
    address dest = address(0xD00D);
    bytes32 ownerTag = bytes32(uint256(0xAA));
    bytes32 ownerTag2 = bytes32(uint256(0xBB));

    uint16 constant GLOBAL_BPS = 2000;
    uint16 constant PROJECT_BPS = 1000;
    uint16 constant NFT_BPS = 0;
    uint16 constant POT_BPS = 1000;
    uint16 constant GAMES_POT_BPS = 6500;

    function setUp() public virtual {
        mona = new TestMona();
        factory = new StakingFactory(1 days);
        registry = new MatroidRegistry(
            address(mona),
            address(factory),
            1 weeks,
            10,
            1_000e18
        );
        kit = new MatroidKit(address(registry));
        registry.setMatroidKit(address(kit));
        globalPool = new GlobalStakingPool(address(mona), 1 days);
        verifier = new AlwaysTrueVerifier();
        roots = new MockRoots();
        kit.setVerification(address(verifier), address(roots));

        acl = new GandaAccessControl();
        blacklist = new GandaBlacklist(address(acl));
        games = new GandaGames(
            address(verifier),
            address(roots),
            address(verifier),
            address(acl),
            address(blacklist)
        );
        hub = new GandaHub(
            address(acl),
            address(games),
            address(kit),
            address(globalPool)
        );
        score = new GandaScore(
            address(verifier),
            address(roots),
            address(verifier),
            address(acl),
            address(blacklist),
            address(games),
            address(hub),
            GAMES_POT_BPS,
            2
        );
        hub.setScore(address(score));
        hub.bootstrap("ipfs://ganda", GLOBAL_BPS, PROJECT_BPS, NFT_BPS, POT_BPS);

        council = new GandaCouncil(
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

        paymaster = new GandaPaymaster(address(games), address(this), 1 ether);
    }

    function publishGame() internal returns (uint256) {
        return
            games.publishGame(
                hex"01",
                bytes32(uint256(1)),
                bytes32(uint256(2)),
                ownerTag,
                scorer,
                "ipfs://game"
            );
    }

    function publishGame2() internal returns (uint256) {
        return
            games.publishGame(
                hex"01",
                bytes32(uint256(1)),
                bytes32(uint256(3)),
                ownerTag2,
                scorer2,
                "ipfs://game2"
            );
    }

    function fundAndFlowIn(
        uint256 gameId,
        address gameScorer,
        address fromPlayer,
        uint256 amount
    ) internal {
        mona.mint(fromPlayer, amount);
        vm.prank(fromPlayer);
        mona.approve(address(registry), amount);
        vm.prank(gameScorer);
        hub.monaIn(gameId, fromPlayer, amount, dest);
    }
}
