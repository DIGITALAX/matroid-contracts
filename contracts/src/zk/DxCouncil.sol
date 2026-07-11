// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";
import {IBalancePool} from "./IBalancePool.sol";
import {ISemaphore} from "@semaphore-protocol/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "@semaphore-protocol/contracts/interfaces/ISemaphoreGroups.sol";

interface IBlacklist {
    function setBanned(address who, bool value) external;
}

/// dx.app's own governance. It only touches dx.app concerns: banning/unbanning
/// wallets on the shared dx Blacklist and adjusting its own quorum. Fuel/paymaster
/// governance lives in SponsorCouncil (matroid) and is deliberately NOT here.
contract DxCouncil {
    enum Kind {
        Ban,
        SetQuorum,
        SetWindow,
        SetBucket
    }

    uint64 public constant MIN_VOTING_WINDOW = 1 minutes;

    struct Proposal {
        uint256 identityRoot;
        bytes32 poolRoot;
        uint8 bucket;
        uint64 start;
        uint64 end;
        bool exists;
        bool executed;
        Kind kind;
        address wallet;
        bool banned;
        uint256 value;
    }

    IVerifier public immutable votingVerifier;
    ISemaphore public immutable semaphore;
    uint256 public immutable groupId;
    IBalancePool public immutable pool;
    IBlacklist public immutable blacklist;
    uint256 public immutable quorumFloor;
    uint64 public votingWindow;
    uint256 public quorum;

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;
    mapping(uint256 => mapping(uint8 => uint256)) public tally;

    event ProposalCreated(uint256 indexed id, Kind kind, address indexed wallet, bool banned, uint256 value, uint64 end, string contentUri);
    event Voted(uint256 indexed id, uint8 choice, uint256 nullifier);
    event Executed(uint256 indexed id, Kind kind, address indexed wallet);
    event QuorumChanged(uint256 newQuorum);
    event WindowChanged(uint64 newWindow);

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
    error BadWindow();
    error BadBucket();

    constructor(
        address votingVerifierAddress,
        address semaphoreAddress,
        uint256 groupId_,
        address poolAddress,
        address blacklistAddress,
        uint64 votingWindow_,
        uint256 quorum_,
        uint256 quorumFloor_
    ) {
        if (quorum_ < quorumFloor_) revert BelowFloor();
        if (votingWindow_ < MIN_VOTING_WINDOW) revert BadWindow();
        votingVerifier = IVerifier(votingVerifierAddress);
        semaphore = ISemaphore(semaphoreAddress);
        groupId = groupId_;
        pool = IBalancePool(poolAddress);
        blacklist = IBlacklist(blacklistAddress);
        votingWindow = votingWindow_;
        quorum = quorum_;
        quorumFloor = quorumFloor_;
    }

    function proposeBan(address wallet, bool banned, string calldata contentUri) external returns (uint256) {
        return _propose(Kind.Ban, wallet, banned, 0, contentUri);
    }

    function proposeQuorum(uint256 newQuorum, string calldata contentUri) external returns (uint256) {
        if (newQuorum < quorumFloor) revert BelowFloor();
        return _propose(Kind.SetQuorum, address(0), false, newQuorum, contentUri);
    }

    function proposeWindow(uint256 newWindow, string calldata contentUri) external returns (uint256) {
        if (newWindow < MIN_VOTING_WINDOW) revert BadWindow();
        return _propose(Kind.SetWindow, address(0), false, newWindow, contentUri);
    }

    function proposeBucket(uint8 newBucket, string calldata contentUri) external returns (uint256) {
        if (newBucket >= pool.bucketCount()) revert BadBucket();
        return _propose(Kind.SetBucket, address(0), false, uint256(newBucket), contentUri);
    }

    function _propose(
        Kind kind,
        address wallet,
        bool banned,
        uint256 value,
        string memory contentUri
    ) internal returns (uint256 id) {
        id = proposalCount;
        proposalCount = id + 1;
        uint64 start = uint64(block.timestamp);
        uint64 end = start + votingWindow;
        uint8 bucket = pool.activeBucket();
        proposals[id] = Proposal({
            identityRoot: ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId),
            poolRoot: pool.currentRoot(bucket),
            bucket: bucket,
            start: start,
            end: end,
            exists: true,
            executed: false,
            kind: kind,
            wallet: wallet,
            banned: banned,
            value: value
        });
        emit ProposalCreated(id, kind, wallet, banned, value, end, contentUri);
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
        uint256 yes = tally[proposalId][1];
        if (yes < quorum || yes <= tally[proposalId][0]) revert Rejected();

        p.executed = true;
        if (p.kind == Kind.Ban) {
            blacklist.setBanned(p.wallet, p.banned);
        } else if (p.kind == Kind.SetQuorum) {
            if (p.value < quorumFloor) revert BelowFloor();
            quorum = p.value;
            emit QuorumChanged(p.value);
        } else if (p.kind == Kind.SetWindow) {
            if (p.value < MIN_VOTING_WINDOW) revert BadWindow();
            votingWindow = uint64(p.value);
            emit WindowChanged(uint64(p.value));
        } else {
            pool.setActiveBucket(uint8(p.value));
        }
        emit Executed(proposalId, p.kind, p.wallet);
    }
}
