// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaLibrary.sol";
import "./GandaAccessControl.sol";
import "./GandaBlacklist.sol";
import "./GandaGames.sol";
import "./GandaHub.sol";
import "./GandaScore.sol";
import {IdentityActionBase} from "../zk/IdentityActionBase.sol";

interface IGandaPaymasterGoverned {
    function setCap(address target, uint256 cap) external;
}

contract GandaCouncil is IdentityActionBase {
    bytes4 public constant PROPOSE_TAG = bytes4(keccak256("gandaCouncil.propose"));
    bytes4 public constant VOTE_TAG = bytes4(keccak256("gandaCouncil.vote"));

    uint8 public constant KIND_BAN_GAME = 0;
    uint8 public constant KIND_UNBAN_GAME = 1;
    uint8 public constant KIND_BAN_TAG = 2;
    uint8 public constant KIND_SET_SPLITS = 3;
    uint8 public constant KIND_SET_VOTE_DURATION = 4;
    uint8 public constant KIND_SET_QUORUM = 5;
    uint8 public constant KIND_SET_PAYMASTER_CAP = 6;
    uint8 public constant KIND_SET_POT_PARAMS = 7;
    uint8 public constant KIND_ADMIN_REMOVE_GAME = 8;

    GandaAccessControl public immutable accessControl;
    GandaBlacklist public immutable blacklist;
    GandaGames public immutable games;
    GandaHub public immutable hub;
    GandaScore public immutable score;
    address public paymaster;

    uint256 public voteDuration;
    uint256 public quorum;
    uint256 public proposalCount;

    mapping(uint256 => GandaLibrary.Proposal) public proposals;
    mapping(uint256 => mapping(bytes32 => bool)) public usedVoteNullifier;

    event Proposed(uint256 indexed proposalId, uint8 kind, uint256 target, bytes32 tagTarget, uint256 value, string uri);
    event Voted(uint256 indexed proposalId, bytes32 indexed nullifier, bool support);
    event Executed(uint256 indexed proposalId, bool passed);
    event PaymasterSet(address paymaster);

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    constructor(
        address actionVerifierAddress,
        address rootsAddress,
        address accessControlAddress,
        address blacklistAddress,
        address gamesAddress,
        address hubAddress,
        address scoreAddress,
        uint256 voteDurationSeconds,
        uint256 quorumValue
    ) IdentityActionBase(actionVerifierAddress, rootsAddress) {
        if (
            accessControlAddress == address(0) ||
            blacklistAddress == address(0) ||
            gamesAddress == address(0) ||
            hubAddress == address(0) ||
            scoreAddress == address(0)
        ) revert GandaErrors.ZeroAddress();
        if (voteDurationSeconds == 0 || quorumValue == 0) revert GandaErrors.InvalidInput();
        accessControl = GandaAccessControl(accessControlAddress);
        blacklist = GandaBlacklist(blacklistAddress);
        games = GandaGames(gamesAddress);
        hub = GandaHub(hubAddress);
        score = GandaScore(scoreAddress);
        voteDuration = voteDurationSeconds;
        quorum = quorumValue;
    }

    function setPaymaster(address paymasterAddress) external onlyAdmin {
        if (paymasterAddress == address(0)) revert GandaErrors.ZeroAddress();
        if (paymaster != address(0)) revert GandaErrors.AlreadySet();
        paymaster = paymasterAddress;
        emit PaymasterSet(paymasterAddress);
    }

    function propose(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier,
        uint8 kind,
        uint256 target,
        bytes32 tagTarget,
        uint256 value,
        string calldata uri
    ) external returns (uint256 proposalId) {
        if (kind > KIND_ADMIN_REMOVE_GAME) revert GandaErrors.InvalidInput();
        proposalId = proposalCount + 1;
        bytes32 payloadHash = keccak256(
            abi.encode(kind, target, tagTarget, value, keccak256(bytes(uri)))
        );
        _verifyAction(proof, PROPOSE_TAG, proposalId, payloadHash, nullifier, merkleRoot);

        proposalCount = proposalId;
        proposals[proposalId] = GandaLibrary.Proposal({
            kind: kind,
            target: target,
            tagTarget: tagTarget,
            value: value,
            yes: 0,
            no: 0,
            start: uint64(block.timestamp),
            end: uint64(block.timestamp + voteDuration),
            executed: false,
            uri: uri
        });
        emit Proposed(proposalId, kind, target, tagTarget, value, uri);
    }

    function vote(
        uint256 proposalId,
        bool support,
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes32 nullifier
    ) external {
        GandaLibrary.Proposal storage proposal = proposals[proposalId];
        if (proposal.start == 0) revert GandaErrors.NotFound();
        if (block.timestamp >= proposal.end) revert GandaErrors.VotingClosed();
        if (usedVoteNullifier[proposalId][nullifier]) revert GandaErrors.NullifierUsed();
        usedVoteNullifier[proposalId][nullifier] = true;

        bytes32 payloadHash = keccak256(abi.encode(proposalId, support));
        _verifyAction(proof, VOTE_TAG, proposalId, payloadHash, nullifier, merkleRoot);

        if (support) {
            proposal.yes += 1;
        } else {
            proposal.no += 1;
        }
        emit Voted(proposalId, nullifier, support);
    }

    function execute(uint256 proposalId) external {
        GandaLibrary.Proposal storage proposal = proposals[proposalId];
        if (proposal.start == 0) revert GandaErrors.NotFound();
        if (block.timestamp < proposal.end) revert GandaErrors.VotingOpen();
        if (proposal.executed) revert GandaErrors.AlreadyExecuted();
        proposal.executed = true;

        bool passed = (proposal.yes + proposal.no >= quorum) && (proposal.yes > proposal.no);
        if (passed) {
            _apply(proposal);
        }
        emit Executed(proposalId, passed);
    }

    function getProposal(uint256 proposalId) external view returns (GandaLibrary.Proposal memory) {
        return proposals[proposalId];
    }

    function _apply(GandaLibrary.Proposal storage proposal) private {
        uint8 kind = proposal.kind;
        if (kind == KIND_BAN_GAME) {
            blacklist.setGameBan(proposal.target, true);
        } else if (kind == KIND_UNBAN_GAME) {
            blacklist.setGameBan(proposal.target, false);
        } else if (kind == KIND_BAN_TAG) {
            blacklist.setTagBan(proposal.tagTarget, true);
        } else if (kind == KIND_SET_SPLITS) {
            hub.setSplits(
                uint16(proposal.value >> 48),
                uint16(proposal.value >> 32),
                uint16(proposal.value >> 16),
                uint16(proposal.value)
            );
        } else if (kind == KIND_SET_VOTE_DURATION) {
            if (proposal.value == 0) revert GandaErrors.InvalidInput();
            voteDuration = proposal.value;
        } else if (kind == KIND_SET_QUORUM) {
            if (proposal.value == 0) revert GandaErrors.InvalidInput();
            quorum = proposal.value;
        } else if (kind == KIND_SET_PAYMASTER_CAP) {
            if (paymaster == address(0)) revert GandaErrors.ZeroAddress();
            IGandaPaymasterGoverned(paymaster).setCap(
                address(uint160(proposal.target)),
                proposal.value
            );
        } else if (kind == KIND_SET_POT_PARAMS) {
            score.setParams(uint16(proposal.value >> 128), uint256(uint128(proposal.value)));
        } else if (kind == KIND_ADMIN_REMOVE_GAME) {
            games.adminRemoveGame(proposal.target);
        }
    }
}
