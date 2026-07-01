// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGasPool {
    function fund() external payable;
}

contract SponsorVault {
    uint256 private constant ACC_PRECISION = 1e18;

    IGasPool public immutable gasPool;
    IERC20 public immutable mona;

    uint256 public totalPoints;
    uint256 public accRewardPerPoint;
    mapping(address => uint256) public points;
    mapping(address => uint256) public rewardDebt;

    event Deposited(address indexed sponsor, uint256 amount, uint256 totalPoints);
    event RewardAdded(uint256 amount, uint256 accRewardPerPoint);
    event Claimed(address indexed sponsor, uint256 amount);

    error ZeroAmount();
    error NoSponsors();
    error TransferFailed();

    constructor(address gasPoolAddress, address monaAddress) {
        gasPool = IGasPool(gasPoolAddress);
        mona = IERC20(monaAddress);
    }

    function deposit() external payable {
        if (msg.value == 0) revert ZeroAmount();
        _settle(msg.sender);

        points[msg.sender] += msg.value;
        totalPoints += msg.value;
        rewardDebt[msg.sender] = points[msg.sender] * accRewardPerPoint / ACC_PRECISION;

        gasPool.fund{value: msg.value}();
        emit Deposited(msg.sender, msg.value, totalPoints);
    }

    function notifyReward(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();
        if (totalPoints == 0) revert NoSponsors();
        if (!mona.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        accRewardPerPoint += amount * ACC_PRECISION / totalPoints;
        emit RewardAdded(amount, accRewardPerPoint);
    }

    function pending(address sponsor) public view returns (uint256) {
        return points[sponsor] * accRewardPerPoint / ACC_PRECISION - rewardDebt[sponsor];
    }

    function claim() external {
        _settle(msg.sender);
    }

    function _settle(address sponsor) internal {
        uint256 amount = pending(sponsor);
        rewardDebt[sponsor] = points[sponsor] * accRewardPerPoint / ACC_PRECISION;
        if (amount > 0) {
            if (!mona.transfer(sponsor, amount)) revert TransferFailed();
            emit Claimed(sponsor, amount);
        }
    }
}
