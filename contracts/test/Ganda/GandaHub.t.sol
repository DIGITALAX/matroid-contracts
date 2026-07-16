// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";

contract GandaHubTest is GandaTestBase {
    function testBootstrapOnlyOnce() public {
        vm.expectRevert(GandaErrors.AlreadySet.selector);
        hub.bootstrap("ipfs://again", GLOBAL_BPS, PROJECT_BPS, NFT_BPS, POT_BPS);
    }

    function testMonaInSplits() public {
        uint256 id = publishGame();
        fundAndFlowIn(id, scorer, player, 100e18);

        (address erc20Pool, , , , ) = registry.projectRewards(address(hub));

        assertEq(globalPool.queuedRewards(), 20e18);
        assertEq(mona.balanceOf(erc20Pool), 10e18);
        assertEq(mona.balanceOf(address(score)), 10e18);
        assertEq(mona.balanceOf(dest), 60e18);
        assertEq(mona.balanceOf(address(hub)), 0);

        uint256 epoch = hub.currentEpoch();
        assertEq(score.epochPot(epoch), 10e18);
        assertEq(hub.gameEpochUniquePlayers(epoch, id), 1);
        assertEq(hub.gameEpochCappedVolume(epoch, id), 100e18);
        assertEq(hub.gameEpochWeight(epoch, id), 100e18);
        assertEq(hub.epochTotalWeight(epoch), 100e18);
    }

    function testMonaInOnlyScorer() public {
        uint256 id = publishGame();
        mona.mint(player, 10e18);
        vm.prank(player);
        mona.approve(address(registry), 10e18);
        vm.prank(player);
        vm.expectRevert(GandaErrors.NotScorer.selector);
        hub.monaIn(id, player, 10e18, dest);
    }

    function testMonaInBannedGameReverts() public {
        uint256 id = publishGame();
        blacklist.setGameBan(id, true);
        vm.prank(scorer);
        vm.expectRevert(GandaErrors.GameNotActive.selector);
        hub.monaIn(id, player, 10e18, dest);
    }

    function testMonaOut() public {
        uint256 id = publishGame();
        mona.mint(scorer, 50e18);
        vm.prank(scorer);
        mona.approve(address(hub), 50e18);
        vm.prank(scorer);
        hub.monaOut(id, player, 50e18);
        assertEq(mona.balanceOf(player), 50e18);
        assertEq(mona.balanceOf(address(hub)), 0);

        uint256 epoch = hub.currentEpoch();
        assertEq(hub.gameEpochUniquePlayers(epoch, id), 1);
        assertEq(hub.gameEpochCappedVolume(epoch, id), 50e18);
    }

    function testVolumeCapPerWallet() public {
        uint256 id = publishGame();
        fundAndFlowIn(id, scorer, player, 900e18);
        fundAndFlowIn(id, scorer, player, 900e18);

        uint256 epoch = hub.currentEpoch();
        assertEq(hub.gameEpochUniquePlayers(epoch, id), 1);
        assertEq(hub.gameEpochCappedVolume(epoch, id), 1_000e18);
    }

    function testWeightAcrossGames() public {
        uint256 id1 = publishGame();
        uint256 id2 = publishGame2();
        fundAndFlowIn(id1, scorer, player, 100e18);
        fundAndFlowIn(id2, scorer2, player2, 300e18);

        uint256 epoch = hub.currentEpoch();
        assertEq(hub.gameEpochWeight(epoch, id1), 100e18);
        assertEq(hub.gameEpochWeight(epoch, id2), 300e18);
        assertEq(hub.epochTotalWeight(epoch), 400e18);
    }

    function testSetSplitsOnlyAdmin() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        hub.setSplits(1000, 500, 0, 500);
    }

    function testSetSplitsOverflowReverts() public {
        vm.expectRevert(GandaErrors.InvalidSplit.selector);
        hub.setSplits(5000, 4000, 1000, 1000);
    }

    function testMonaInVerified() public {
        uint256 id = publishGame();
        mona.mint(player, 100e18);
        vm.prank(player);
        mona.approve(address(registry), 100e18);
        vm.prank(scorer);
        hub.monaInVerified(
            id,
            player,
            100e18,
            dest,
            bytes32(uint256(1)),
            hex"01",
            bytes32(uint256(99))
        );
        assertEq(mona.balanceOf(dest), 60e18);
        uint256 epoch = hub.currentEpoch();
        assertEq(registry.getEpochStats(address(hub), epoch).weightedUniqueUsers, 2);
    }
}
