// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Test-only stand-in for matroid's real Treasury.deposit(uint256), used by
/// PrefabMarket's fallback slice-routing when no sponsors are active yet.
contract TestTreasurySink {
    IERC20 public immutable mona;

    constructor(address monaAddress) {
        mona = IERC20(monaAddress);
    }

    function deposit(uint256 amount) external {
        mona.transferFrom(msg.sender, address(this), amount);
    }
}
