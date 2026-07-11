// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Test-only mintable MONA stand-in for anvil deployment.
contract TestMona is ERC20 {
    constructor() ERC20("Test MONA", "MONA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
