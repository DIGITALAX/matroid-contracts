// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Test-only stand-in for the real MatroidPaymaster gas pool (zkSync-only, deployed
/// separately). Just absorbs SponsorVault deposits for anvil (plain-EVM) testing.
contract TestGasPool {
    function fund() external payable {}
    receive() external payable {}
}
