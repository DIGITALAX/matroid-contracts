// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IdentityActionBase, IIdentityActionRoots} from "./IdentityActionBase.sol";

contract IdentityAction is IdentityActionBase {
    mapping(bytes4 => mapping(uint256 => mapping(bytes32 => bool))) public usedNullifier;

    event Action(bytes4 indexed actionTag, uint256 indexed scope, bytes32 nullifier, bytes32 payloadHash);

    error NullifierUsed();

    constructor(address verifierAddress, address rootsAddress)
        IdentityActionBase(verifierAddress, rootsAddress)
    {}

    function act(
        bytes calldata proof,
        bytes32 merkleRoot,
        bytes4 actionTag,
        uint256 scopeSeed,
        bytes32 payloadHash,
        bytes32 nullifier
    ) external {
        uint256 scope = _verifyAction(proof, actionTag, scopeSeed, payloadHash, nullifier, merkleRoot);
        if (usedNullifier[actionTag][scope][nullifier]) revert NullifierUsed();
        usedNullifier[actionTag][scope][nullifier] = true;
        emit Action(actionTag, scope, nullifier, payloadHash);
    }
}
