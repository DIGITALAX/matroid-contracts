// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "@semaphore-protocol/contracts/interfaces/ISemaphoreGroups.sol";

interface ISnapshotSource {
    function currentRoot() external view returns (bytes32);
}

interface ITreasuryGovernance {
    function setBudgets(uint256 newBaseBudget, uint256 newPerProjectBudget) external;
    function extendDuration(uint256 newDuration) external;
}

contract MatroidAnonGovernance {
    struct Proposal {
        uint256 identityRoot;
        bytes32 balanceRoot;
        uint64 start;
        uint64 end;
        bool exists;
        bool executed;
        uint256 baseBudget;
        uint256 perProjectBudget;
        uint256 newDuration;
    }

    uint256 public constant BALANCE_LINK_SCOPE = uint256(keccak256("matroid.balance-link"));

    IVerifier public immutable votingVerifier;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    ISnapshotSource public immutable snapshots;
    ITreasuryGovernance public immutable treasury;
    uint128 public immutable minBalance;
    uint64 public immutable votingWindow;
    uint256 public immutable quorumFloor;
    uint256 public quorum;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(uint256 indexed id, uint256 baseBudget, uint256 perProjectBudget, uint256 newDuration, uint64 end);
    event Voted(uint256 indexed id, uint8 choice, uint256 nullifier);
    event Executed(uint256 indexed id, bool passed, bool applied);

    error NoProposal();
    error VotingClosed();
    error VotingOpen();
    error InvalidChoice();
    error AlreadyExecuted();
    error BadProof();
    error BadScope();
    error StaleRoot();
    error BelowFloor();

    constructor(
        address votingVerifierAddress,
        address semaphoreAddress,
        uint256 groupId_,
        address snapshotAddress,
        address treasuryAddress,
        uint128 minBalance_,
        uint64 votingWindow_,
        uint256 quorum_,
        uint256 quorumFloor_
    ) {
        if (quorum_ < quorumFloor_) revert BelowFloor();
        votingVerifier = IVerifier(votingVerifierAddress);
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;
        snapshots = ISnapshotSource(snapshotAddress);
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
            identityRoot: ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId),
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

    function vote(
        ISemaphore.SemaphoreProof calldata voteProof,
        ISemaphore.SemaphoreProof calldata balanceLinkProof,
        bytes calldata balanceZkProof,
        uint256 proposalId
    ) external {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert NoProposal();
        if (block.timestamp < p.start || block.timestamp >= p.end) revert VotingClosed();
        if (voteProof.scope != proposalId) revert BadScope();
        if (voteProof.merkleTreeRoot != p.identityRoot) revert StaleRoot();
        uint8 choice = uint8(voteProof.message);
        if (choice > 1) revert InvalidChoice();

        semaphore.validateProof(groupId, voteProof);

        if (balanceLinkProof.scope != BALANCE_LINK_SCOPE) revert BadScope();
        if (balanceLinkProof.merkleTreeRoot != p.identityRoot) revert StaleRoot();
        if (!semaphore.verifyProof(groupId, balanceLinkProof)) revert BadProof();

        bytes32[] memory balancePub = new bytes32[](3);
        balancePub[0] = p.balanceRoot;
        balancePub[1] = bytes32(uint256(minBalance));
        balancePub[2] = bytes32(balanceLinkProof.nullifier);
        if (!votingVerifier.verify(balanceZkProof, balancePub)) revert BadProof();

        tally[proposalId][choice] += 1;
        emit Voted(proposalId, choice, voteProof.nullifier);
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
