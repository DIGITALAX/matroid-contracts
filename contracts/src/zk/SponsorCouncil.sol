// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "@semaphore-protocol/contracts/interfaces/ISemaphoreGroups.sol";

interface ISnapshotSource {
    function currentRoot() external view returns (bytes32);
}

interface IPaymasterAdmin {
    function setBlacklisted(address project, bool banned) external;
    function setCap(address project, uint256 cap) external;
}

interface IBlacklist {
    function setBlacklisted(address actor, bool banned) external;
}

interface ICyberWeight {
    function setWeight(uint256 projectId, address swagman, uint256 weight) external;
}

contract SponsorCouncil {
    enum Kind {
        Blacklist,
        Cap,
        SetQuorum,
        Ban,
        SetCyberWeight
    }

    struct Proposal {
        uint256 identityRoot;
        bytes32 balanceRoot;
        uint64 start;
        uint64 end;
        bool exists;
        bool executed;
        Kind kind;
        address target;
        address project;
        bool banned;
        uint256 value;
        uint256 extra;
    }

    uint256 public constant BALANCE_LINK_SCOPE = uint256(keccak256("matroid.balance-link"));

    IVerifier public immutable votingVerifier;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    ISnapshotSource public immutable snapshots;
    IPaymasterAdmin public immutable paymaster;
    uint128 public immutable minBalance;
    uint64 public immutable votingWindow;
    uint256 public immutable quorumFloor;
    uint256 public quorum;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(uint256 indexed id, Kind kind, address indexed project, bool banned, uint256 value, uint64 end, string contentUri);
    event Voted(uint256 indexed id, uint8 choice, uint256 nullifier);
    event Executed(uint256 indexed id, Kind kind, address indexed project);
    event QuorumChanged(uint256 newQuorum);

    error NoProposal();
    error VotingClosed();
    error VotingOpen();
    error InvalidChoice();
    error AlreadyExecuted();
    error Rejected();
    error BadProof();
    error BadScope();
    error StaleRoot();
    error BelowFloor();

    constructor(
        address votingVerifierAddress,
        address semaphoreAddress,
        uint256 groupId_,
        address snapshotAddress,
        address paymasterAddress,
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
        paymaster = IPaymasterAdmin(paymasterAddress);
        minBalance = minBalance_;
        votingWindow = votingWindow_;
        quorum = quorum_;
        quorumFloor = quorumFloor_;
    }

    function proposeBlacklist(address project, bool banned, string calldata contentUri) external returns (uint256) {
        return _propose(Kind.Blacklist, address(0), project, banned, 0, 0, contentUri);
    }

    function proposeCap(address project, uint256 cap, string calldata contentUri) external returns (uint256) {
        return _propose(Kind.Cap, address(0), project, false, cap, 0, contentUri);
    }

    function proposeQuorum(uint256 newQuorum, string calldata contentUri) external returns (uint256) {
        if (newQuorum < quorumFloor) revert BelowFloor();
        return _propose(Kind.SetQuorum, address(0), address(0), false, newQuorum, 0, contentUri);
    }

    function proposeBan(address target, address actor, bool banned, string calldata contentUri) external returns (uint256) {
        return _propose(Kind.Ban, target, actor, banned, 0, 0, contentUri);
    }

    function proposeSetCyberWeight(
        address cyberRegistry,
        uint256 projectId,
        address swagman,
        uint256 weight,
        string calldata contentUri
    ) external returns (uint256) {
        return _propose(Kind.SetCyberWeight, cyberRegistry, swagman, false, weight, projectId, contentUri);
    }

    function _propose(
        Kind kind,
        address target,
        address project,
        bool banned,
        uint256 value,
        uint256 extra,
        string memory contentUri
    ) internal returns (uint256 id) {
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
            kind: kind,
            target: target,
            project: project,
            banned: banned,
            value: value,
            extra: extra
        });
        emit ProposalCreated(id, kind, project, banned, value, end, contentUri);
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
        uint256 yes = tally[proposalId][1];
        if (yes < quorum || yes <= tally[proposalId][0]) revert Rejected();

        p.executed = true;
        if (p.kind == Kind.Blacklist) {
            paymaster.setBlacklisted(p.project, p.banned);
        } else if (p.kind == Kind.Cap) {
            paymaster.setCap(p.project, p.value);
        } else if (p.kind == Kind.Ban) {
            IBlacklist(p.target).setBlacklisted(p.project, p.banned);
        } else if (p.kind == Kind.SetCyberWeight) {
            ICyberWeight(p.target).setWeight(p.extra, p.project, p.value);
        } else {
            if (p.value < quorumFloor) revert BelowFloor();
            quorum = p.value;
            emit QuorumChanged(p.value);
        }
        emit Executed(proposalId, p.kind, p.project);
    }
}
