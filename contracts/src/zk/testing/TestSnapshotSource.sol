// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Test-only stand-in for ISnapshotSource (MonaBalanceTree): a constant root,
/// used only by unit tests to exercise the governance flow.
contract TestSnapshotSource {
    function currentRoot() external pure returns (bytes32) {
        return bytes32(0);
    }
}
