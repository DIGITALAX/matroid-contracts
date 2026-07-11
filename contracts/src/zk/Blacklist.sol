// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Central blacklist consulted by every dx.computer registry. A banned wallet
/// cannot publish kits, create products/grants/agents, buy, or comment.
/// Setters (the registries that expose ban actions, and the council) are
/// authorized by the admin.
contract Blacklist {
    address public immutable admin;
    mapping(address => bool) public banned;
    mapping(address => bool) public setter;

    event Banned(address indexed who, bool banned, address indexed by);
    event SetterChanged(address indexed setter, bool allowed);

    error NotAdmin();
    error NotSetter();

    constructor(address admin_) {
        admin = admin_;
        setter[admin_] = true;
    }

    function setSetter(address who, bool allowed) external {
        if (msg.sender != admin) revert NotAdmin();
        setter[who] = allowed;
        emit SetterChanged(who, allowed);
    }

    function setBanned(address who, bool value) external {
        if (!setter[msg.sender]) revert NotSetter();
        banned[who] = value;
        emit Banned(who, value, msg.sender);
    }

    function isBanned(address who) external view returns (bool) {
        return banned[who];
    }
}
