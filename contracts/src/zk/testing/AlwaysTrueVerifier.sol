// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IVerifier} from "../IVerifier.sol";

/// Test-only stand-in for the real NXP-attestation enrollment verifier.
/// Accepts any proof unconditionally. NEVER deploy this outside anvil/local testing —
/// production must use the real Noir-circuit-derived enrollment verifier.
contract AlwaysTrueVerifier is IVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}
