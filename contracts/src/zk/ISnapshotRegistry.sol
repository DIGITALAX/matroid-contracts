// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

interface ISnapshotRegistry {
    function currentRoot() external view returns (bytes32);

    function isKnownBalanceRoot(bytes32 root) external view returns (bool);
}
