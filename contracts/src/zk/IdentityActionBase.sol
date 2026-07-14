// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "./IVerifier.sol";

interface IIdentityActionRoots {
    function isKnownRoot(bytes32 root) external view returns (bool);
}

abstract contract IdentityActionBase {
    IVerifier public immutable verifier;
    IIdentityActionRoots public immutable identityRoots;

    bytes8 public constant DOMAIN = 0x64782d6163742d76;
    uint8 public constant DOMAIN_VERSION = 1;

    error UnknownRoot();
    error BadProof();
    error ZeroAddress();

    constructor(address verifierAddress, address rootsAddress) {
        if (verifierAddress == address(0) || rootsAddress == address(0)) revert ZeroAddress();
        verifier = IVerifier(verifierAddress);
        identityRoots = IIdentityActionRoots(rootsAddress);
    }

    function scopeOf(bytes4 actionTag, uint256 scopeSeed) public view returns (uint256) {
        return uint256(keccak256(abi.encode(address(this), actionTag, scopeSeed))) >> 8;
    }

    function digestOf(bytes4 actionTag, uint256 scope, bytes32 payloadHash) public view returns (bytes32) {
        return sha256(
            abi.encodePacked(
                DOMAIN,
                DOMAIN_VERSION,
                uint64(block.chainid),
                address(this),
                actionTag,
                bytes32(scope),
                payloadHash
            )
        );
    }

    function _verifyAction(
        bytes calldata proof,
        bytes4 actionTag,
        uint256 scopeSeed,
        bytes32 payloadHash,
        bytes32 nullifier,
        bytes32 merkleRoot
    ) internal view returns (uint256 scope) {
        if (!identityRoots.isKnownRoot(merkleRoot)) revert UnknownRoot();
        scope = scopeOf(actionTag, scopeSeed);
        bytes32 digest = digestOf(actionTag, scope, payloadHash);
        bytes32[] memory pub = new bytes32[](5);
        pub[0] = bytes32(uint256(uint128(bytes16(digest))));
        pub[1] = bytes32(uint256(uint128(uint256(digest))));
        pub[2] = merkleRoot;
        pub[3] = bytes32(scope);
        pub[4] = nullifier;
        if (!verifier.verify(proof, pub)) revert BadProof();
    }
}
