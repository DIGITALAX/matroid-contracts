// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";

contract GandaBlacklist {
    GandaAccessControl public immutable accessControl;

    mapping(uint256 => bool) public bannedGame;
    mapping(bytes32 => bool) public bannedTag;
    mapping(address => bool) public setter;

    event GameBanSet(uint256 indexed gameId, bool banned, address indexed by);
    event TagBanSet(bytes32 indexed ownerTag, bool banned, address indexed by);
    event SetterChanged(address indexed who, bool allowed);

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    modifier onlySetter() {
        if (!setter[msg.sender] && !accessControl.isAdmin(msg.sender)) {
            revert GandaErrors.Unauthorized();
        }
        _;
    }

    constructor(address accessControlAddress) {
        if (accessControlAddress == address(0)) revert GandaErrors.ZeroAddress();
        accessControl = GandaAccessControl(accessControlAddress);
    }

    function setSetter(address who, bool allowed) external onlyAdmin {
        if (who == address(0)) revert GandaErrors.ZeroAddress();
        setter[who] = allowed;
        emit SetterChanged(who, allowed);
    }

    function setGameBan(uint256 gameId, bool banned) external onlySetter {
        bannedGame[gameId] = banned;
        emit GameBanSet(gameId, banned, msg.sender);
    }

    function setTagBan(bytes32 ownerTag, bool banned) external onlySetter {
        bannedTag[ownerTag] = banned;
        emit TagBanSet(ownerTag, banned, msg.sender);
    }

    function isGameBanned(uint256 gameId) external view returns (bool) {
        return bannedGame[gameId];
    }

    function isTagBanned(bytes32 ownerTag) external view returns (bool) {
        return bannedTag[ownerTag];
    }
}
