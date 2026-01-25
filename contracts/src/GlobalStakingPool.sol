// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MatroidErrors.sol";

contract GlobalStakingPool is ReentrancyGuard {
    using SafeERC20 for IERC20;
    uint256 private constant RATE_SCALE = 1e18;

    IERC20 public immutable mona;
    uint256 public immutable rewardDuration;
    uint256 public totalStaked;
    uint256 public rewardPerTokenStored;
    uint256 public lastUpdateTime;
    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public queuedRewards;

    mapping(address => uint256) public staked;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public pendingRewards;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardNotified(uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    constructor(address monaToken, uint256 rewardDurationSeconds) {
        if (monaToken == address(0)) revert MatroidErrors.ZeroAddress();
        if (rewardDurationSeconds == 0) revert MatroidErrors.InvalidDuration();
        mona = IERC20(monaToken);
        rewardDuration = rewardDurationSeconds;
    }

    function notifyReward(uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        mona.safeTransferFrom(msg.sender, address(this), amount);
        if (totalStaked == 0) {
            queuedRewards += amount;
            emit RewardNotified(amount);
            return;
        }
        _updateReward(address(0));
        _startRewardStream(amount);
        emit RewardNotified(amount);
    }

    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        uint256 previousTotal = totalStaked;
        _updateReward(msg.sender);
        mona.safeTransferFrom(msg.sender, address(this), amount);
        totalStaked += amount;
        staked[msg.sender] += amount;
        userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;
        if (previousTotal == 0 && queuedRewards > 0) {
            _updateReward(address(0));
            _startRewardStream(0);
        }
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        if (staked[msg.sender] < amount) revert MatroidErrors.InsufficientStake();
        _updateReward(msg.sender);
        staked[msg.sender] -= amount;
        totalStaked -= amount;
        userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;
        if (totalStaked == 0) {
            _pauseRewards();
        }
        mona.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    function claim() external nonReentrant {
        _updateReward(msg.sender);
        uint256 reward = pendingRewards[msg.sender];
        if (reward == 0) return;
        pendingRewards[msg.sender] = 0;
        userRewardPerTokenPaid[msg.sender] = rewardPerTokenStored;
        mona.safeTransfer(msg.sender, reward);
        emit Claimed(msg.sender, reward);
    }

    function _updateReward(address user) internal {
        rewardPerTokenStored = _rewardPerToken();
        lastUpdateTime = _lastTimeRewardApplicable();
        if (user == address(0)) return;
        pendingRewards[user] = _earned(user);
        userRewardPerTokenPaid[user] = rewardPerTokenStored;
    }

    function _lastTimeRewardApplicable() internal view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function _rewardPerToken() internal view returns (uint256) {
        if (totalStaked == 0) return rewardPerTokenStored;
        uint256 delta = _lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + ((delta * rewardRate) / totalStaked);
    }

    function _earned(address user) internal view returns (uint256) {
        uint256 delta = rewardPerTokenStored - userRewardPerTokenPaid[user];
        return pendingRewards[user] + ((staked[user] * delta) / RATE_SCALE);
    }

    function _startRewardStream(uint256 amount) internal {
        uint256 total = amount + queuedRewards;
        if (total == 0) return;
        uint256 totalTokens = total;
        if (block.timestamp < periodFinish) {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = (remaining * rewardRate) / RATE_SCALE;
            totalTokens += leftover;
        }
        rewardRate = (totalTokens * RATE_SCALE) / rewardDuration;
        uint256 distributed = (rewardRate * rewardDuration) / RATE_SCALE;
        queuedRewards = totalTokens - distributed;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardDuration;
    }

    function _pauseRewards() internal {
        uint256 remaining = 0;
        if (block.timestamp < periodFinish) {
            remaining = ((periodFinish - block.timestamp) * rewardRate) / RATE_SCALE;
        }
        if (remaining > 0) {
            queuedRewards += remaining;
        }
        rewardRate = 0;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp;
    }
}
