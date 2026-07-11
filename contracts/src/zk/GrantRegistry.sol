// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBlacklist {
    function isBanned(address who) external view returns (bool);
    function setBanned(address who, bool value) external;
}

contract GrantRegistry {
    uint256 private constant ACC = 1e18;

    IERC20 public immutable mona;
    IBlacklist public immutable blacklist;

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
    mapping(uint256 => mapping(address => uint256)) public shares;
    mapping(uint256 => uint256) public accRewardPerShare;
    mapping(uint256 => mapping(address => uint256)) public rewardDebt;
    mapping(uint256 => mapping(address => uint256)) public pending;
    mapping(uint256 => address) public ruggedCreator;

    event GrantCreated(uint256 indexed grantId, uint256 indexed kitId, address indexed creator, bytes32 purposeHash, string contentUri, uint256 budget);
    event GrantUpdated(uint256 indexed grantId, bytes32 purposeHash, string contentUri, uint256 budget);
    event GrantRemoved(uint256 indexed grantId);
    event GrantFunded(uint256 indexed grantId, address indexed funder, uint256 amount, uint256 totalFunderShares);
    event RewardAdded(uint256 indexed grantId, uint256 amount);
    event Claimed(uint256 indexed grantId, address indexed funder, uint256 amount);

    error NoGrant();
    error ZeroAmount();
    error NoFunders();
    error Banned();
    error TransferFailed();
    error NotCreator();
    error HasFunders();
    error NotRugged();
    error NoShares();

    constructor(address monaAddress, address blacklistAddress) {
        mona = IERC20(monaAddress);
        blacklist = IBlacklist(blacklistAddress);
    }

    function createGrant(
        uint256 kitId,
        bytes32 purposeHash,
        string calldata contentUri,
        uint256 budget
    ) external returns (uint256 grantId) {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        grantId = grantCount + 1;
        grantCount = grantId;
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
        emit GrantCreated(grantId, kitId, msg.sender, purposeHash, contentUri, budget);
    }

    function updateGrant(
        uint256 grantId,
        bytes32 purposeHash,
        string calldata contentUri,
        uint256 budget
    ) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (g.creator != msg.sender) revert NotCreator();
        if (g.totalShares != 0) revert HasFunders();
        g.purposeHash = purposeHash;
        g.contentUri = contentUri;
        g.budget = budget;
        emit GrantUpdated(grantId, purposeHash, contentUri, budget);
    }

    function removeGrant(uint256 grantId) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (g.creator != msg.sender) revert NotCreator();
        if (g.totalShares != 0) {
            ruggedCreator[grantId] = g.creator;
        }
        delete grants[grantId];
        emit GrantRemoved(grantId);
    }

    function blacklistRuggedCreator(uint256 grantId) external {
        address creator = ruggedCreator[grantId];
        if (creator == address(0)) revert NotRugged();
        if (shares[grantId][msg.sender] == 0) revert NoShares();
        blacklist.setBanned(creator, true);
    }

    function fundGrant(uint256 grantId, uint256 amount) external {
        Grant storage g = grants[grantId];
        if (!g.exists) revert NoGrant();
        if (blacklist.isBanned(msg.sender)) revert Banned();
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

    function kitOf(uint256 grantId) external view returns (uint256) {
        return grants[grantId].kitId;
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
