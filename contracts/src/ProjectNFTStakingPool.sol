// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MatroidLibrary.sol";
import "./MatroidErrors.sol";

contract ProjectNFTStakingPool is ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;
    uint256 private constant RATE_SCALE = 1e18;

    IERC20 public immutable mona;
    address public immutable project;
    uint256 public immutable rewardDuration;

    uint256 public totalWeight;
    address[] public rewardTokens;
    address[] public whitelistedNfts;

    mapping(address => uint256) public nftWeight;
    mapping(address => bool) public nftWhitelisted;
    mapping(address => MatroidLibrary.RewardToken) public rewardInfo;
    mapping(address => uint256) public stakedWeight;
    mapping(address => mapping(address => uint256)) public rewardDebt;
    mapping(address => mapping(address => uint256)) public pendingRewards;
    mapping(address => mapping(uint256 => address)) public stakedOwner;
    mapping(address => mapping(uint256 => uint256)) public stakedTokenWeight;

    event RewardTokenAdded(address indexed token);
    event RewardTokenRemoved(address indexed token);
    event RewardNotified(address indexed token, uint256 amount);
    event NftWhitelisted(address indexed nft, uint256 weight);
    event NftWeightUpdated(address indexed nft, uint256 weight);
    event NftStaked(address indexed user, address indexed nft, uint256 tokenId, uint256 weight);
    event NftUnstaked(address indexed user, address indexed nft, uint256 tokenId, uint256 weight);
    event Claimed(address indexed user, address indexed token, uint256 amount);

    constructor(address monaToken, address projectAddress, uint256 rewardDurationSeconds) {
        if (monaToken == address(0)) revert MatroidErrors.ZeroAddress();
        if (projectAddress == address(0)) revert MatroidErrors.ZeroAddress();
        if (rewardDurationSeconds == 0) revert MatroidErrors.InvalidDuration();
        mona = IERC20(monaToken);
        project = projectAddress;
        rewardDuration = rewardDurationSeconds;
        _addRewardToken(monaToken);
    }

    modifier onlyProject() {
        if (msg.sender != project) revert MatroidErrors.NotProject();
        _;
    }

    function setNftWeight(address nft, uint256 weight) external onlyProject {
        if (nft == address(0)) revert MatroidErrors.ZeroAddress();
        if (!nftWhitelisted[nft]) {
            nftWhitelisted[nft] = true;
            whitelistedNfts.push(nft);
            nftWeight[nft] = weight;
            emit NftWhitelisted(nft, weight);
            return;
        }
        nftWeight[nft] = weight;
        emit NftWeightUpdated(nft, weight);
    }

    function addRewardToken(address token) external onlyProject {
        _addRewardToken(token);
    }

    function removeRewardToken(address token) external onlyProject {
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        if (!info.enabled) revert MatroidErrors.TokenDisabled();
        if (info.queuedRewards > 0) revert MatroidErrors.TokenInUse();
        if (info.periodFinish > block.timestamp) revert MatroidErrors.TokenInUse();
        info.enabled = false;
        _removeRewardToken(token);
        emit RewardTokenRemoved(token);
    }

    function rewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    function rewardTokenAt(uint256 index) external view returns (address) {
        return rewardTokens[index];
    }

    function whitelistCount() external view returns (uint256) {
        return whitelistedNfts.length;
    }

    function whitelistAt(uint256 index) external view returns (address) {
        return whitelistedNfts[index];
    }

    function notifyRewardToken(address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        if (!info.enabled) revert MatroidErrors.TokenDisabled();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        if (totalWeight == 0) {
            info.queuedRewards += amount;
            emit RewardNotified(token, amount);
            return;
        }
        _updateRewardToken(address(0), token);
        _startRewardStream(token, amount);
        emit RewardNotified(token, amount);
    }

    function stakeNFT(address nft, uint256 tokenId) external nonReentrant {
        uint256 weight = nftWeight[nft];
        if (weight == 0) revert MatroidErrors.NotWhitelistedNFT();
        if (stakedOwner[nft][tokenId] != address(0)) revert MatroidErrors.NFTAlreadyStaked();
        uint256 previousTotal = totalWeight;
        _updateRewards(msg.sender);
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);
        stakedOwner[nft][tokenId] = msg.sender;
        stakedTokenWeight[nft][tokenId] = weight;
        totalWeight += weight;
        stakedWeight[msg.sender] += weight;
        _syncRewardDebt(msg.sender);
        if (previousTotal == 0) {
            _startQueuedRewards();
        }
        emit NftStaked(msg.sender, nft, tokenId, weight);
    }

    function unstakeNFT(address nft, uint256 tokenId) external nonReentrant {
        address owner = stakedOwner[nft][tokenId];
        if (owner == address(0)) revert MatroidErrors.NFTNotStaked();
        if (owner != msg.sender) revert MatroidErrors.NotNFTOwner();
        _updateRewards(msg.sender);
        uint256 weight = stakedTokenWeight[nft][tokenId];
        delete stakedOwner[nft][tokenId];
        delete stakedTokenWeight[nft][tokenId];
        totalWeight -= weight;
        stakedWeight[msg.sender] -= weight;
        _syncRewardDebt(msg.sender);
        if (totalWeight == 0) {
            _pauseRewards();
        }
        IERC721(nft).safeTransferFrom(address(this), msg.sender, tokenId);
        emit NftUnstaked(msg.sender, nft, tokenId, weight);
    }

    function claim(address token) external nonReentrant {
        _updateRewardToken(msg.sender, token);
        uint256 reward = pendingRewards[msg.sender][token];
        if (reward == 0) return;
        pendingRewards[msg.sender][token] = 0;
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        rewardDebt[msg.sender][token] = info.rewardPerTokenStored;
        IERC20(token).safeTransfer(msg.sender, reward);
        emit Claimed(msg.sender, token, reward);
    }

    function _addRewardToken(address token) internal {
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        if (info.enabled) revert MatroidErrors.TokenExists();
        info.enabled = true;
        rewardTokens.push(token);
        emit RewardTokenAdded(token);
    }

    function _removeRewardToken(address token) internal {
        uint256 length = rewardTokens.length;
        for (uint256 i = 0; i < length; i++) {
            if (rewardTokens[i] == token) {
                rewardTokens[i] = rewardTokens[length - 1];
                rewardTokens.pop();
                return;
            }
        }
    }

    function _updateRewards(address user) internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            _updateRewardToken(user, rewardTokens[i]);
        }
    }

    function _updateRewardToken(address user, address token) internal {
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        info.rewardPerTokenStored = _rewardPerToken(token);
        info.lastUpdateTime = _lastTimeRewardApplicable(token);
        if (user == address(0)) return;
        pendingRewards[user][token] = _earned(user, token);
        rewardDebt[user][token] = info.rewardPerTokenStored;
    }

    function _syncRewardDebt(address user) internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            MatroidLibrary.RewardToken storage info = rewardInfo[token];
            rewardDebt[user][token] = info.rewardPerTokenStored;
        }
    }

    function _startQueuedRewards() internal {
        if (totalWeight == 0) return;
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            MatroidLibrary.RewardToken storage info = rewardInfo[token];
            if (info.queuedRewards == 0) continue;
            _updateRewardToken(address(0), token);
            _startRewardStream(token, 0);
        }
    }

    function _lastTimeRewardApplicable(address token) internal view returns (uint256) {
        uint256 finish = rewardInfo[token].periodFinish;
        return block.timestamp < finish ? block.timestamp : finish;
    }

    function _rewardPerToken(address token) internal view returns (uint256) {
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        if (totalWeight == 0) return info.rewardPerTokenStored;
        uint256 delta = _lastTimeRewardApplicable(token) - info.lastUpdateTime;
        return info.rewardPerTokenStored + ((delta * info.rewardRate) / totalWeight);
    }

    function _earned(address user, address token) internal view returns (uint256) {
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        uint256 delta = info.rewardPerTokenStored - rewardDebt[user][token];
        return pendingRewards[user][token] + ((stakedWeight[user] * delta) / RATE_SCALE);
    }

    function _startRewardStream(address token, uint256 amount) internal {
        MatroidLibrary.RewardToken storage info = rewardInfo[token];
        uint256 total = amount + info.queuedRewards;
        if (total == 0) return;
        uint256 totalTokens = total;
        if (block.timestamp < info.periodFinish) {
            uint256 remaining = info.periodFinish - block.timestamp;
            uint256 leftover = (remaining * info.rewardRate) / RATE_SCALE;
            totalTokens += leftover;
        }
        info.rewardRate = (totalTokens * RATE_SCALE) / rewardDuration;
        uint256 distributed = (info.rewardRate * rewardDuration) / RATE_SCALE;
        info.queuedRewards = totalTokens - distributed;
        info.lastUpdateTime = block.timestamp;
        info.periodFinish = block.timestamp + rewardDuration;
    }

    function _pauseRewards() internal {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            MatroidLibrary.RewardToken storage info = rewardInfo[token];
            uint256 remaining = 0;
            if (block.timestamp < info.periodFinish) {
                remaining = ((info.periodFinish - block.timestamp) * info.rewardRate) / RATE_SCALE;
            }
            if (remaining > 0) {
                info.queuedRewards += remaining;
            }
            info.rewardRate = 0;
            info.lastUpdateTime = block.timestamp;
            info.periodFinish = block.timestamp;
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
