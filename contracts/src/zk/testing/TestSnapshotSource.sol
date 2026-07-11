// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Test-only stand-in for ISnapshotSource (MonaBalanceTree). The public anvil
/// deploy pairs it with AlwaysTrueVerifier, which accepts any balance proof, so
/// a constant root is enough to exercise the governance flow end to end.
contract TestSnapshotSource {
    function currentRoot() external pure returns (bytes32) {
        return bytes32(0);
    }
}
