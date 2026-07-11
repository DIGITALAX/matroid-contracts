// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

interface IBalancePool {
    function activeBucket() external view returns (uint8);

    function bucketCount() external view returns (uint8);

    function denomination(uint8 bucket) external view returns (uint256);

    function currentRoot(uint8 bucket) external view returns (bytes32);

    function setActiveBucket(uint8 bucket) external;
}
