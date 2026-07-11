// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNFT is ERC721 {
    uint256 public nextId;

    constructor() ERC721("Test NFT", "TNFT") {}

    function mint(address to, uint256 count) external {
        for (uint256 i = 0; i < count; i++) {
            _mint(to, ++nextId);
        }
    }
}
