// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MatroidErrors.sol";

interface ITreasuryGovernance {
    function setBudgets(uint256 newBaseBudget, uint256 newPerProjectBudget) external;
    function extendDuration(uint256 newDuration) external;
}

contract MatroidGovernance is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Proposal {
        uint256 baseBudget;
        uint256 perProjectBudget;
        uint256 newDuration;
        uint256 endTime;
        uint256 yesWeight;
        uint256 noWeight;
        bool executed;
    }

    IERC20 public immutable mona;
    ITreasuryGovernance public immutable treasury;
    uint256 public immutable votingWindow;
    uint256 public immutable minProposeStake;
    uint16 public immutable quorumBps;
    uint16 public immutable thresholdBps;

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => uint256)) public lockedStake;
    mapping(uint256 => mapping(address => bool)) public support;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed id, uint256 baseBudget, uint256 perProjectBudget, uint256 endTime);
    event Voted(uint256 indexed id, address indexed voter, bool inFavor, uint256 amount);
    event VoteCancelled(uint256 indexed id, address indexed voter, uint256 amount);
    event ProposalExecuted(uint256 indexed id, bool passed, bool applied);
    event StakeWithdrawn(uint256 indexed id, address indexed voter, uint256 amount);

    constructor(
        address monaToken,
        address treasuryAddress,
        uint256 votingWindowSeconds,
        uint256 minProposeStakeAmount,
        uint16 quorumBpsValue,
        uint16 thresholdBpsValue
    ) {
        if (monaToken == address(0) || treasuryAddress == address(0)) {
            revert MatroidErrors.ZeroAddress();
        }
        if (votingWindowSeconds == 0) revert MatroidErrors.InvalidDuration();
        if (minProposeStakeAmount == 0) revert MatroidErrors.ZeroAmount();
        if (quorumBpsValue == 0 || quorumBpsValue > 10_000) {
            revert MatroidErrors.InvalidThreshold();
        }
        if (thresholdBpsValue == 0 || thresholdBpsValue > 10_000) {
            revert MatroidErrors.InvalidThreshold();
        }
        mona = IERC20(monaToken);
        treasury = ITreasuryGovernance(treasuryAddress);
        votingWindow = votingWindowSeconds;
        minProposeStake = minProposeStakeAmount;
        quorumBps = quorumBpsValue;
        thresholdBps = thresholdBpsValue;
    }

    function propose(
        uint256 newBaseBudget,
        uint256 newPerProjectBudget,
        uint256 newTargetDuration
    ) external nonReentrant returns (uint256 id) {
        id = proposalCount;
        proposalCount = id + 1;

        Proposal storage p = proposals[id];
        p.baseBudget = newBaseBudget;
        p.perProjectBudget = newPerProjectBudget;
        p.newDuration = newTargetDuration;
        p.endTime = block.timestamp + votingWindow;

        mona.safeTransferFrom(msg.sender, address(this), minProposeStake);
        lockedStake[id][msg.sender] = minProposeStake;
        support[id][msg.sender] = true;
        hasVoted[id][msg.sender] = true;
        p.yesWeight = minProposeStake;

        emit ProposalCreated(id, newBaseBudget, newPerProjectBudget, p.endTime);
        emit Voted(id, msg.sender, true, minProposeStake);
    }

    function vote(uint256 id, bool inFavor, uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        Proposal storage p = proposals[id];
        if (p.endTime == 0) revert MatroidErrors.ProposalNotFound();
        if (block.timestamp > p.endTime) revert MatroidErrors.VoteWindowClosed();
        if (hasVoted[id][msg.sender]) revert MatroidErrors.AlreadyVoted();

        mona.safeTransferFrom(msg.sender, address(this), amount);
        lockedStake[id][msg.sender] = amount;
        support[id][msg.sender] = inFavor;
        hasVoted[id][msg.sender] = true;
        if (inFavor) {
            p.yesWeight += amount;
        } else {
            p.noWeight += amount;
        }
        emit Voted(id, msg.sender, inFavor, amount);
    }

    function cancelVote(uint256 id) external nonReentrant {
        Proposal storage p = proposals[id];
        if (p.endTime == 0) revert MatroidErrors.ProposalNotFound();
        if (block.timestamp > p.endTime) revert MatroidErrors.VoteWindowClosed();
        if (!hasVoted[id][msg.sender]) revert MatroidErrors.NotVoted();

        uint256 amount = lockedStake[id][msg.sender];
        lockedStake[id][msg.sender] = 0;
        hasVoted[id][msg.sender] = false;
        if (support[id][msg.sender]) {
            p.yesWeight -= amount;
        } else {
            p.noWeight -= amount;
        }
        mona.safeTransfer(msg.sender, amount);
        emit VoteCancelled(id, msg.sender, amount);
    }

    function execute(uint256 id) external nonReentrant {
        Proposal storage p = proposals[id];
        if (p.endTime == 0) revert MatroidErrors.ProposalNotFound();
        if (block.timestamp <= p.endTime) revert MatroidErrors.VoteWindowOpen();
        if (p.executed) revert MatroidErrors.AlreadyExecuted();
        p.executed = true;

        uint256 total = p.yesWeight + p.noWeight;
        uint256 quorum = (mona.totalSupply() * quorumBps) / 10_000;
        bool passed = total >= quorum &&
            (p.yesWeight * 10_000) / total >= thresholdBps;

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
        emit ProposalExecuted(id, passed, applied);
    }

    function withdraw(uint256 id) external nonReentrant {
        Proposal storage p = proposals[id];
        if (p.endTime == 0) revert MatroidErrors.ProposalNotFound();
        if (block.timestamp <= p.endTime) revert MatroidErrors.VoteWindowOpen();
        uint256 amount = lockedStake[id][msg.sender];
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        lockedStake[id][msg.sender] = 0;
        mona.safeTransfer(msg.sender, amount);
        emit StakeWithdrawn(id, msg.sender, amount);
    }
}
