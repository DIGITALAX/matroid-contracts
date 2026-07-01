// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

interface IVerifier {
    function verify(bytes calldata proof, bytes32[] calldata publicInputs) external view returns (bool);
}
