// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

interface IPoseidon {
    function poseidon(bytes32[2] calldata input) external pure returns (bytes32);
}
