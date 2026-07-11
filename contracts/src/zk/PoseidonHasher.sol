// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {PoseidonT3} from "poseidon-solidity/PoseidonT3.sol";
import {IPoseidon} from "./IPoseidon.sol";

contract PoseidonHasher is IPoseidon {
    function poseidon(bytes32[2] calldata input) external pure returns (bytes32) {
        return bytes32(PoseidonT3.hash([uint256(input[0]), uint256(input[1])]));
    }
}
