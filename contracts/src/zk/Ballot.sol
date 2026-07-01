// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IdentityRegistry} from "./IdentityRegistry.sol";
import {ISnapshotRegistry} from "./ISnapshotRegistry.sol";

contract Ballot {
    struct Proposal {
        bytes32 identityRoot;
        bytes32 balanceRoot;
        uint64 start;
        uint64 end;
        bool exists;
    }

    IVerifier public immutable votingVerifier;
    IdentityRegistry public immutable registry;
    ISnapshotRegistry public immutable snapshots;
    uint128 public immutable minBalance;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    mapping(uint256 => mapping(bytes32 => bool)) public usedNullifier;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(
        uint256 indexed proposalId,
        bytes32 identityRoot,
        bytes32 balanceRoot,
        uint64 start,
        uint64 end
    );
    event Voted(uint256 indexed proposalId, uint8 choice, bytes32 nullifier);

    error ZeroWindow();
    error NoProposal();
    error VotingClosed();
    error InvalidChoice();
    error AlreadyVoted();
    error BadProof();

    constructor(
        address votingVerifierAddress,
        address registryAddress,
        address snapshotRegistryAddress,
        uint128 minBalance_
    ) {
        votingVerifier = IVerifier(votingVerifierAddress);
        registry = IdentityRegistry(registryAddress);
        snapshots = ISnapshotRegistry(snapshotRegistryAddress);
        minBalance = minBalance_;
    }

    function createProposal(uint64 votingWindow) external returns (uint256 proposalId) {
        if (votingWindow == 0) revert ZeroWindow();

        proposalId = proposalCount;
        proposalCount = proposalId + 1;

        bytes32 identityRoot = registry.currentRoot();
        bytes32 balanceRoot = snapshots.currentRoot();
        uint64 start = uint64(block.timestamp);
        uint64 end = start + votingWindow;

        proposals[proposalId] = Proposal({
            identityRoot: identityRoot,
            balanceRoot: balanceRoot,
            start: start,
            end: end,
            exists: true
        });

        emit ProposalCreated(proposalId, identityRoot, balanceRoot, start, end);
    }

    function vote(
        bytes calldata proof,
        uint256 proposalId,
        uint8 choice,
        bytes32 nullifier
    ) external {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert NoProposal();
        if (block.timestamp < p.start || block.timestamp >= p.end) revert VotingClosed();
        if (choice > 1) revert InvalidChoice();
        if (usedNullifier[proposalId][nullifier]) revert AlreadyVoted();

        bytes32[] memory pubInputs = new bytes32[](6);
        pubInputs[0] = p.identityRoot;
        pubInputs[1] = bytes32(proposalId);
        pubInputs[2] = bytes32(uint256(choice));
        pubInputs[3] = p.balanceRoot;
        pubInputs[4] = bytes32(uint256(minBalance));
        pubInputs[5] = nullifier;
        if (!votingVerifier.verify(proof, pubInputs)) revert BadProof();

        usedNullifier[proposalId][nullifier] = true;
        tally[proposalId][choice] += 1;

        emit Voted(proposalId, choice, nullifier);
    }
}
