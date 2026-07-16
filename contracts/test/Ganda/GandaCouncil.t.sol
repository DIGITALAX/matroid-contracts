// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaTestBase.sol";
import {GandaErrors} from "../../src/Ganda/GandaErrors.sol";
import {GandaPaymaster} from "../../src/Ganda/GandaPaymaster.sol";

contract GandaCouncilTest is GandaTestBase {
    function proposeBan(uint256 gameId) internal returns (uint256) {
        return
            council.propose(
                hex"01",
                bytes32(uint256(1)),
                bytes32(uint256(10)),
                council.KIND_BAN_GAME(),
                gameId,
                bytes32(0),
                0,
                "ipfs://proposal"
            );
    }

    function voteYes(uint256 proposalId, uint256 nullifierSeed) internal {
        council.vote(
            proposalId,
            true,
            hex"01",
            bytes32(uint256(1)),
            bytes32(nullifierSeed)
        );
    }

    function testProposeAndVoteAndExecuteBan() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        assertEq(proposalId, 1);

        voteYes(proposalId, 100);
        voteYes(proposalId, 101);

        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertTrue(blacklist.isGameBanned(gameId));
        assertFalse(games.isActive(gameId));
    }

    function testVoteSameNullifierReverts() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        voteYes(proposalId, 100);
        vm.expectRevert(GandaErrors.NullifierUsed.selector);
        voteYes(proposalId, 100);
    }

    function testVoteAfterEndReverts() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        vm.warp(block.timestamp + 3 days + 1);
        vm.expectRevert(GandaErrors.VotingClosed.selector);
        voteYes(proposalId, 100);
    }

    function testExecuteBeforeEndReverts() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        vm.expectRevert(GandaErrors.VotingOpen.selector);
        council.execute(proposalId);
    }

    function testQuorumNotMetDoesNotApply() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        voteYes(proposalId, 100);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertFalse(blacklist.isGameBanned(gameId));
    }

    function testExecuteTwiceReverts() public {
        uint256 gameId = publishGame();
        uint256 proposalId = proposeBan(gameId);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        vm.expectRevert(GandaErrors.AlreadyExecuted.selector);
        council.execute(proposalId);
    }

    function testSetSplitsProposal() public {
        uint256 value = (uint256(1500) << 48) |
            (uint256(500) << 32) |
            (uint256(0) << 16) |
            uint256(2000);
        uint256 proposalId = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(11)),
            council.KIND_SET_SPLITS(),
            0,
            bytes32(0),
            value,
            "ipfs://splits"
        );
        voteYes(proposalId, 100);
        voteYes(proposalId, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertEq(hub.potBps(), 2000);
    }

    function testSetPotParamsProposal() public {
        uint256 value = (uint256(5000) << 128) | uint256(4);
        uint256 proposalId = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(12)),
            council.KIND_SET_POT_PARAMS(),
            0,
            bytes32(0),
            value,
            "ipfs://pot"
        );
        voteYes(proposalId, 100);
        voteYes(proposalId, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertEq(score.gamesPotBps(), 5000);
        assertEq(score.claimWindowEpochs(), 4);
    }

    function testSetVoteDurationAndQuorumProposals() public {
        uint256 p1 = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(13)),
            council.KIND_SET_VOTE_DURATION(),
            0,
            bytes32(0),
            5 days,
            "ipfs://duration"
        );
        voteYes(p1, 100);
        voteYes(p1, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(p1);
        assertEq(council.voteDuration(), 5 days);

        uint256 p2 = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(14)),
            council.KIND_SET_QUORUM(),
            0,
            bytes32(0),
            3,
            "ipfs://quorum"
        );
        voteYes(p2, 200);
        voteYes(p2, 201);
        vm.warp(block.timestamp + 5 days + 1);
        council.execute(p2);
        assertEq(council.quorum(), 3);
    }

    function testPaymasterCapProposal() public {
        GandaPaymaster pm = new GandaPaymaster(
            address(games),
            address(council),
            1 ether
        );
        council.setPaymaster(address(pm));

        uint256 proposalId = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(15)),
            council.KIND_SET_PAYMASTER_CAP(),
            uint256(uint160(address(games))),
            bytes32(0),
            5 ether,
            "ipfs://cap"
        );
        voteYes(proposalId, 100);
        voteYes(proposalId, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertEq(pm.capOf(address(games)), 5 ether);
    }

    function testAdminRemoveGameProposal() public {
        uint256 gameId = publishGame();
        uint256 proposalId = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(16)),
            council.KIND_ADMIN_REMOVE_GAME(),
            gameId,
            bytes32(0),
            0,
            "ipfs://remove"
        );
        voteYes(proposalId, 100);
        voteYes(proposalId, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertFalse(games.isActive(gameId));
    }

    function testBanTagProposal() public {
        uint256 proposalId = council.propose(
            hex"01",
            bytes32(uint256(1)),
            bytes32(uint256(17)),
            council.KIND_BAN_TAG(),
            0,
            ownerTag,
            0,
            "ipfs://bantag"
        );
        voteYes(proposalId, 100);
        voteYes(proposalId, 101);
        vm.warp(block.timestamp + 3 days + 1);
        council.execute(proposalId);
        assertTrue(blacklist.isTagBanned(ownerTag));
    }
}
