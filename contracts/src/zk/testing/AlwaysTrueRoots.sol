// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Test-only stand-in for IIdentityRoots. Only exercised by anonymous (chip-gated)
/// paths, never by public paths — safe to deploy for public-path anvil testing.
contract AlwaysTrueRoots {
    function isKnownRoot(bytes32) external pure returns (bool) {
        return true;
    }
}
