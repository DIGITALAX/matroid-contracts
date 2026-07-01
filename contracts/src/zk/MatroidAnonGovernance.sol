// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";

interface IRootSource {
    function currentRoot() external view returns (bytes32);
}

interface ITreasuryGovernance {
    function setBudgets(uint256 newBaseBudget, uint256 newPerProjectBudget) external;
    function extendDuration(uint256 newDuration) external;
}

contract MatroidAnonGovernance {
    struct Proposal {
        bytes32 identityRoot;
        bytes32 balanceRoot;
        uint64 start;
        uint64 end;
        bool exists;
        bool executed;
        uint256 baseBudget;
        uint256 perProjectBudget;
        uint256 newDuration;
    }

    IVerifier public immutable votingVerifier;
    IRootSource public immutable identity;
    IRootSource public immutable snapshots;
    ITreasuryGovernance public immutable treasury;
    uint128 public immutable minBalance;
    uint64 public immutable votingWindow;
    uint256 public immutable quorumFloor;
    uint256 public quorum;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(uint256 => mapping(bytes32 => bool)) public usedNullifier;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(uint256 indexed id, uint256 baseBudget, uint256 perProjectBudget, uint256 newDuration, uint64 end);
    event Voted(uint256 indexed id, uint8 choice, bytes32 nullifier);
    event Executed(uint256 indexed id, bool passed, bool applied);

    error NoProposal();
    error VotingClosed();
    error VotingOpen();
    error InvalidChoice();
    error AlreadyVoted();
    error AlreadyExecuted();
    error BadProof();
    error BelowFloor();

    constructor(
        address votingVerifierAddress,
        address identityAddress,
        address snapshotAddress,
        address treasuryAddress,
        uint128 minBalance_,
        uint64 votingWindow_,
        uint256 quorum_,
        uint256 quorumFloor_
    ) {
        if (quorum_ < quorumFloor_) revert BelowFloor();
        votingVerifier = IVerifier(votingVerifierAddress);
        identity = IRootSource(identityAddress);
        snapshots = IRootSource(snapshotAddress);
        treasury = ITreasuryGovernance(treasuryAddress);
        minBalance = minBalance_;
        votingWindow = votingWindow_;
        quorum = quorum_;
        quorumFloor = quorumFloor_;
    }

    function propose(uint256 baseBudget, uint256 perProjectBudget, uint256 newDuration)
        external
        returns (uint256 id)
    {
        id = proposalCount;
        proposalCount = id + 1;
        uint64 start = uint64(block.timestamp);
        uint64 end = start + votingWindow;
        proposals[id] = Proposal({
            identityRoot: identity.currentRoot(),
            balanceRoot: snapshots.currentRoot(),
            start: start,
            end: end,
            exists: true,
            executed: false,
            baseBudget: baseBudget,
            perProjectBudget: perProjectBudget,
            newDuration: newDuration
        });
        emit ProposalCreated(id, baseBudget, perProjectBudget, newDuration, end);
    }

    function vote(bytes calldata proof, uint256 proposalId, uint8 choice, bytes32 nullifier) external {
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

    function execute(uint256 proposalId) external {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert NoProposal();
        if (block.timestamp < p.end) revert VotingOpen();
        if (p.executed) revert AlreadyExecuted();
        p.executed = true;

        uint256 yes = tally[proposalId][1];
        uint256 no = tally[proposalId][0];
        bool passed = yes >= quorum && yes > no;

        bool applied;
        if (passed) {
            try treasury.setBudgets(p.baseBudget, p.perProjectBudget) {
                applied = true;
            } catch {
                applied = false;
            }
            if (p.newDuration > 0) {
                try treasury.extendDuration(p.newDuration) {} catch {}
            }
        }
        emit Executed(proposalId, passed, applied);
    }
}
