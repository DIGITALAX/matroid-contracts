// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract GrantRegistry {
    uint256 private constant ACC = 1e18;
    uint16 public constant BPS = 10000;

    IERC20 public immutable mona;
    address public immutable council;

    struct Grant {
        uint256 kitId;
        address creator;
        bytes32 purposeHash;
        string contentUri;
        uint256 budget;
        uint256 raised;
        uint256 totalShares;
        bool exists;
    }

    mapping(uint256 => Grant) public grants;
    uint256 public grantCount;
    mapping(uint256 => uint16) public salesShareBps;
    mapping(uint256 => mapping(address => uint256)) public shares;
    mapping(uint256 => uint256) public accRewardPerShare;
    mapping(uint256 => mapping(address => uint256)) public rewardDebt;
    mapping(uint256 => mapping(address => uint256)) public pending;
    mapping(address => bool) public creatorBanned;

    event GrantCreated(uint256 indexed grantId, uint256 indexed kitId, address indexed creator, bytes32 purposeHash, string contentUri, uint256 budget, uint16 salesShareBps);
    event GrantRemoved(uint256 indexed grantId);
    event GrantFunded(uint256 indexed grantId, address indexed funder, uint256 amount, uint256 totalFunderShares);
    event RewardAdded(uint256 indexed grantId, uint256 amount);
    event Claimed(uint256 indexed grantId, address indexed funder, uint256 amount);
    event CreatorBanned(address indexed creator, bool banned);

    error NoGrant();
    error ZeroAmount();
    error NoFunders();
    error Banned();
    error NotCouncil();
    error BadShare();
    error TransferFailed();
    error NotCreator();
    error HasFunders();

    constructor(address monaAddress, address councilAddress) {
        mona = IERC20(monaAddress);
        council = councilAddress;
    }

    function setBlacklisted(address creator, bool banned) external {
        if (msg.sender != council) revert NotCouncil();
        creatorBanned[creator] = banned;
        emit CreatorBanned(creator, banned);
    }

    function createGrant(
        uint256 kitId,
        bytes32 purposeHash,
        string calldata contentUri,
        uint256 budget,
        uint16 salesShareBps_
    ) external returns (uint256 grantId) {
        if (creatorBanned[msg.sender]) revert Banned();
        if (salesShareBps_ > BPS) revert BadShare();
        grantId = grantCount;
        grantCount = grantId + 1;
        grants[grantId] = Grant({
            kitId: kitId,
            creator: msg.sender,
            purposeHash: purposeHash,
            contentUri: contentUri,
            budget: budget,
            raised: 0,
            totalShares: 0,
            exists: true
        });
        salesShareBps[grantId] = salesShareBps_;
        emit GrantCreated(grantId, kitId, msg.sender, purposeHash, contentUri, budget, salesShareBps_);
    }

    function removeGrant(uint256 grantId) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (g.creator != msg.sender) revert NotCreator();
        if (g.totalShares != 0) revert HasFunders();
        g.exists = false;
        emit GrantRemoved(grantId);
    }

    function fundGrant(uint256 grantId, uint256 amount) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (amount == 0) revert ZeroAmount();

        _settle(grantId, msg.sender);
        if (!mona.transferFrom(msg.sender, g.creator, amount)) revert TransferFailed();

        shares[grantId][msg.sender] += amount;
        g.raised += amount;
        g.totalShares += amount;
        rewardDebt[grantId][msg.sender] = shares[grantId][msg.sender] * accRewardPerShare[grantId] / ACC;
        emit GrantFunded(grantId, msg.sender, amount, shares[grantId][msg.sender]);
    }

    function notifyReward(uint256 grantId, uint256 amount) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (amount == 0) revert ZeroAmount();
        if (g.totalShares == 0) revert NoFunders();
        if (!mona.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        accRewardPerShare[grantId] += amount * ACC / g.totalShares;
        emit RewardAdded(grantId, amount);
    }

    function totalSharesOf(uint256 grantId) external view returns (uint256) {
        return grants[grantId].totalShares;
    }

    function pendingReward(uint256 grantId, address funder) external view returns (uint256) {
        uint256 accrued = shares[grantId][funder] * accRewardPerShare[grantId] / ACC;
        return pending[grantId][funder] + accrued - rewardDebt[grantId][funder];
    }

    function claim(uint256 grantId) external {
        _settle(grantId, msg.sender);
        uint256 amount = pending[grantId][msg.sender];
        if (amount == 0) return;
        pending[grantId][msg.sender] = 0;
        if (!mona.transfer(msg.sender, amount)) revert TransferFailed();
        emit Claimed(grantId, msg.sender, amount);
    }

    function _settle(uint256 grantId, address funder) internal {
        uint256 accrued = shares[grantId][funder] * accRewardPerShare[grantId] / ACC;
        pending[grantId][funder] += accrued - rewardDebt[grantId][funder];
        rewardDebt[grantId][funder] = accrued;
    }
}
