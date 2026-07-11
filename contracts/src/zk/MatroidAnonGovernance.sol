// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IBalancePool} from "./IBalancePool.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "@semaphore-protocol/contracts/interfaces/ISemaphoreGroups.sol";

interface ITreasuryGovernance {
    function setBudgets(uint256 newBaseBudget, uint256 newPerProjectBudget) external;
    function extendDuration(uint256 newDuration) external;
}

interface IPaymasterGovernance {
    function setCap(address project, uint256 cap) external;
    function setDefaultCap(uint256 cap) external;
    function setRegistered(address project, bool active) external;
    function setBlacklisted(address project, bool banned) external;
}

contract MatroidAnonGovernance {
    enum Kind {
        Budget,
        Bucket,
        PmCap,
        PmDefaultCap,
        PmRegister,
        PmBlacklist
    }

    struct Proposal {
        uint256 identityRoot;
        bytes32 poolRoot;
        uint8 bucket;
        uint64 start;
        uint64 end;
        bool exists;
        bool executed;
        Kind kind;
        uint8 newBucket;
        address pmProject;
        bool pmFlag;
        uint256 pmValue;
        uint256 baseBudget;
        uint256 perProjectBudget;
        uint256 newDuration;
    }

    IVerifier public immutable votingVerifier;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    IBalancePool public immutable pool;
    ITreasuryGovernance public immutable treasury;
    IPaymasterGovernance public immutable paymaster;
    uint64 public immutable votingWindow;
    uint256 public immutable quorumFloor;
    uint256 public quorum;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(uint256 indexed id, uint256 baseBudget, uint256 perProjectBudget, uint256 newDuration, uint64 end);
    event BucketProposalCreated(uint256 indexed id, uint8 newBucket, uint64 end);
    event PaymasterProposalCreated(uint256 indexed id, Kind kind, address project, uint256 value, bool flag, uint64 end);
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
    error BadBucket();
    error ZeroAddress();

    constructor(
        address votingVerifierAddress,
        address semaphoreAddress,
        uint256 groupId_,
        address poolAddress,
        address treasuryAddress,
        address paymasterAddress,
        uint64 votingWindow_,
        uint256 quorum_,
        uint256 quorumFloor_
    ) {
        if (quorum_ < quorumFloor_) revert BelowFloor();
        votingVerifier = IVerifier(votingVerifierAddress);
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;
        pool = IBalancePool(poolAddress);
        treasury = ITreasuryGovernance(treasuryAddress);
        paymaster = IPaymasterGovernance(paymasterAddress);
        votingWindow = votingWindow_;
        quorum = quorum_;
        quorumFloor = quorumFloor_;
    }

    function propose(uint256 baseBudget, uint256 perProjectBudget, uint256 newDuration)
        external
        returns (uint256 id)
    {
        id = _create(Kind.Budget);
        Proposal storage p = proposals[id];
        p.baseBudget = baseBudget;
        p.perProjectBudget = perProjectBudget;
        p.newDuration = newDuration;
        emit ProposalCreated(id, baseBudget, perProjectBudget, newDuration, p.end);
    }

    function proposeBucket(uint8 newBucket) external returns (uint256 id) {
        if (newBucket >= pool.bucketCount()) revert BadBucket();
        id = _create(Kind.Bucket);
        Proposal storage p = proposals[id];
        p.newBucket = newBucket;
        emit BucketProposalCreated(id, newBucket, p.end);
    }

    function proposeCap(address project, uint256 cap) external returns (uint256 id) {
        if (project == address(0)) revert ZeroAddress();
        id = _create(Kind.PmCap);
        Proposal storage p = proposals[id];
        p.pmProject = project;
        p.pmValue = cap;
        emit PaymasterProposalCreated(id, Kind.PmCap, project, cap, false, p.end);
    }

    function proposeDefaultCap(uint256 cap) external returns (uint256 id) {
        id = _create(Kind.PmDefaultCap);
        Proposal storage p = proposals[id];
        p.pmValue = cap;
        emit PaymasterProposalCreated(id, Kind.PmDefaultCap, address(0), cap, false, p.end);
    }

    function proposeRegister(address project, bool active) external returns (uint256 id) {
        if (project == address(0)) revert ZeroAddress();
        id = _create(Kind.PmRegister);
        Proposal storage p = proposals[id];
        p.pmProject = project;
        p.pmFlag = active;
        emit PaymasterProposalCreated(id, Kind.PmRegister, project, 0, active, p.end);
    }

    function proposeBlacklist(address project, bool banned) external returns (uint256 id) {
        if (project == address(0)) revert ZeroAddress();
        id = _create(Kind.PmBlacklist);
        Proposal storage p = proposals[id];
        p.pmProject = project;
        p.pmFlag = banned;
        emit PaymasterProposalCreated(id, Kind.PmBlacklist, project, 0, banned, p.end);
    }

    function _create(Kind kind) internal returns (uint256 id) {
        id = proposalCount;
        proposalCount = id + 1;
        uint64 start = uint64(block.timestamp);
        uint64 end = start + votingWindow;
        uint8 bucket = pool.activeBucket();
        Proposal storage p = proposals[id];
        p.identityRoot = ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId);
        p.poolRoot = pool.currentRoot(bucket);
        p.bucket = bucket;
        p.start = start;
        p.end = end;
        p.exists = true;
        p.kind = kind;
    }

    function vote(
        ISemaphore.SemaphoreProof calldata voteProof,
        bytes calldata poolZkProof,
        bytes32 poolRoot,
        uint256 proposalId
    ) external {
        Proposal storage p = proposals[proposalId];
        if (!p.exists) revert NoProposal();
        if (block.timestamp < p.start || block.timestamp >= p.end) revert VotingClosed();
        uint256 scopeVal = uint256(keccak256(abi.encode(address(this), proposalId)));
        if (voteProof.scope != scopeVal) revert BadScope();
        if (voteProof.merkleTreeRoot != p.identityRoot) revert StaleRoot();
        if (poolRoot != p.poolRoot && poolRoot != pool.currentRoot(p.bucket)) revert StaleRoot();
        uint8 choice = uint8(voteProof.message);
        if (choice > 1) revert InvalidChoice();

        semaphore.validateProof(groupId, voteProof);

        bytes32[] memory poolPub = new bytes32[](3);
        poolPub[0] = poolRoot;
        poolPub[1] = bytes32(uint256(keccak256(abi.encode(scopeVal))) >> 8);
        poolPub[2] = bytes32(voteProof.nullifier);
        if (!votingVerifier.verify(poolZkProof, poolPub)) revert BadProof();

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
            if (p.kind == Kind.Budget) {
                try treasury.setBudgets(p.baseBudget, p.perProjectBudget) {
                    applied = true;
                } catch {
                    applied = false;
                }
                if (p.newDuration > 0) {
                    try treasury.extendDuration(p.newDuration) {} catch {}
                }
            } else if (p.kind == Kind.Bucket) {
                try pool.setActiveBucket(p.newBucket) {
                    applied = true;
                } catch {
                    applied = false;
                }
            } else if (p.kind == Kind.PmCap) {
                try paymaster.setCap(p.pmProject, p.pmValue) {
                    applied = true;
                } catch {
                    applied = false;
                }
            } else if (p.kind == Kind.PmDefaultCap) {
                try paymaster.setDefaultCap(p.pmValue) {
                    applied = true;
                } catch {
                    applied = false;
                }
            } else if (p.kind == Kind.PmRegister) {
                try paymaster.setRegistered(p.pmProject, p.pmFlag) {
                    applied = true;
                } catch {
                    applied = false;
                }
            } else {
                try paymaster.setBlacklisted(p.pmProject, p.pmFlag) {
                    applied = true;
                } catch {
                    applied = false;
                }
            }
        }
        emit Executed(proposalId, passed, applied);
    }
}
