// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";

contract GandaScoreTest is GandaTestBase {
    bytes32 playerKey;

    function setUp() public override {
        super.setUp();
        playerKey = bytes32(uint256(uint160(player)));
    }

    function testSubmitScoreOnlyScorer() public {
        uint256 id = publishGame();
        vm.prank(player);
        vm.expectRevert(GandaErrors.NotScorer.selector);
        score.submitScore(id, player, 100);
    }

    function testSubmitAndNota() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        vm.startPrank(scorer);
        score.submitScore(id, player, 300);
        score.submitScore(id, player2, 100);
        vm.stopPrank();

        assertEq(score.epochGameTotalPoints(epoch, id), 400);
        assertEq(score.epochGamePlayerCount(epoch, id), 2);
        assertEq(score.notaOf(epoch, playerKey), (300 * 1e18) / 400);
        assertEq(score.epochGamesWithPoints(epoch), 1);
    }

    function testNotaAcrossGames() public {
        uint256 id1 = publishGame();
        uint256 id2 = publishGame2();
        uint256 epoch = hub.currentEpoch();
        vm.prank(scorer);
        score.submitScore(id1, player, 500);
        vm.startPrank(scorer2);
        score.submitScore(id2, player, 100);
        score.submitScore(id2, player2, 300);
        vm.stopPrank();

        uint256 expected = 1e18 + (100 * 1e18) / 400;
        assertEq(score.notaOf(epoch, playerKey), expected);
        assertEq(score.epochGamesWithPoints(epoch), 2);
    }

    function testPlayerClaim() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id, player, 100);

        vm.warp(block.timestamp + 1 weeks);

        uint256 playersPot = (10e18 * (10_000 - uint256(GAMES_POT_BPS))) / 10_000;
        vm.prank(player);
        score.claim(epoch, player);
        assertEq(mona.balanceOf(player), playersPot);
        assertTrue(score.playerClaimed(epoch, playerKey));
    }

    function testDoubleClaimReverts() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id, player, 100);
        vm.warp(block.timestamp + 1 weeks);
        vm.prank(player);
        score.claim(epoch, player);
        vm.prank(player);
        vm.expectRevert(GandaErrors.AlreadyClaimed.selector);
        score.claim(epoch, player);
    }

    function testClaimBeforeCloseReverts() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id, player, 100);
        vm.prank(player);
        vm.expectRevert(GandaErrors.EpochNotClosed.selector);
        score.claim(epoch, player);
    }

    function testClaimAfterWindowReverts() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id, player, 100);
        vm.warp(block.timestamp + 4 weeks);
        vm.prank(player);
        vm.expectRevert(GandaErrors.ClaimWindowClosed.selector);
        score.claim(epoch, player);
    }

    function testClaimAnon() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        bytes32 nullifier = bytes32(uint256(777));
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScoreAnon(id, nullifier, 100);

        vm.warp(block.timestamp + 1 weeks);

        address fresh = address(0xF4E5);
        score.claimAnon(epoch, hex"01", bytes32(uint256(1)), nullifier, fresh);
        uint256 playersPot = (10e18 * (10_000 - uint256(GAMES_POT_BPS))) / 10_000;
        assertEq(mona.balanceOf(fresh), playersPot);
    }

    function testClaimGame() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id, player, 100);

        vm.warp(block.timestamp + 1 weeks);

        address gameWallet = address(0xFA57);
        score.claimGame(epoch, id, hex"01", gameWallet);
        uint256 gamesPot = (10e18 * uint256(GAMES_POT_BPS)) / 10_000;
        assertEq(mona.balanceOf(gameWallet), gamesPot);
        assertTrue(score.gameClaimed(epoch, id));

        vm.expectRevert(GandaErrors.AlreadyClaimed.selector);
        score.claimGame(epoch, id, hex"01", gameWallet);
    }

    function testGamesPotSplitAcrossGames() public {
        uint256 id1 = publishGame();
        uint256 id2 = publishGame2();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id1, scorer, player, 100e18);
        fundAndFlowIn(id2, scorer2, player2, 300e18);

        vm.warp(block.timestamp + 1 weeks);

        uint256 gamesPot = (40e18 * uint256(GAMES_POT_BPS)) / 10_000;
        address wallet1 = address(0xFA51);
        address wallet2 = address(0xFA52);
        score.claimGame(epoch, id1, hex"01", wallet1);
        score.claimGame(epoch, id2, hex"01", wallet2);
        assertEq(mona.balanceOf(wallet1), (gamesPot * 100e18) / 400e18);
        assertEq(mona.balanceOf(wallet2), (gamesPot * 300e18) / 400e18);
    }

    function testSyncBanExcludesGame() public {
        uint256 id1 = publishGame();
        uint256 id2 = publishGame2();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id1, scorer, player, 100e18);
        vm.prank(scorer);
        score.submitScore(id1, player, 100);
        vm.prank(scorer2);
        score.submitScore(id2, player, 100);

        blacklist.setGameBan(id1, true);
        score.syncBan(epoch, id1);
        assertEq(score.epochBannedWithPoints(epoch), 1);
        assertEq(score.notaOf(epoch, playerKey), 1e18);

        vm.warp(block.timestamp + 1 weeks);
        vm.prank(player);
        score.claim(epoch, player);
        uint256 playersPot = (10e18 * (10_000 - uint256(GAMES_POT_BPS))) / 10_000;
        assertEq(mona.balanceOf(player), playersPot);
    }

    function testRollExpired() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        fundAndFlowIn(id, scorer, player, 100e18);

        vm.warp(block.timestamp + 4 weeks);
        uint256 current = hub.currentEpoch();
        score.rollExpired(epoch);
        assertEq(score.epochPotRemaining(epoch), 0);
        assertEq(score.epochPot(current), 10e18);
    }

    function testEraseMe() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        vm.prank(scorer);
        score.submitScore(id, player, 100);
        assertEq(score.notaOf(epoch, playerKey), 1e18);

        vm.prank(player);
        score.eraseMe(epoch);
        assertEq(score.notaOf(epoch, playerKey), 0);
        assertEq(score.epochGameTotalPoints(epoch, id), 0);
        assertEq(score.epochGamePlayerCount(epoch, id), 0);
    }

    function testEraseMeAnon() public {
        uint256 id = publishGame();
        uint256 epoch = hub.currentEpoch();
        bytes32 nullifier = bytes32(uint256(777));
        vm.prank(scorer);
        score.submitScoreAnon(id, nullifier, 100);

        score.eraseMeAnon(epoch, hex"01", bytes32(uint256(1)), nullifier);
        assertEq(score.notaOf(epoch, nullifier), 0);
    }

    function testNotifyPotOnlyHub() public {
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        score.notifyPot(0, 1, 1e18);
    }

    function testSetParamsOnlyAdmin() public {
        vm.prank(player);
        vm.expectRevert(GandaErrors.Unauthorized.selector);
        score.setParams(5000, 3);
        score.setParams(5000, 3);
        assertEq(score.gamesPotBps(), 5000);
        assertEq(score.claimWindowEpochs(), 3);
    }
}
