// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaLibrary.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract GandaAccessControl {

    struct WhitelistEntry {
        bool active;
        uint256 index;
    }

    mapping(address => bool) private _admins;
    address[] private _whitelist;
    mapping(address => WhitelistEntry) private _whitelistInfo;

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event WhitelistAdded(address indexed nft);
    event WhitelistRemoved(address indexed nft);

    modifier onlyAdmin() {
        if (!_admins[msg.sender]) revert GandaErrors.Unauthorized();
        _;
    }

    constructor() {
        _admins[msg.sender] = true;
        emit AdminAdded(msg.sender);
    }

    function addAdmin(address admin) external onlyAdmin {
        if (admin == address(0)) revert GandaErrors.InvalidInput();
        if (_admins[admin]) revert GandaErrors.AlreadyExists();
        _admins[admin] = true;
        emit AdminAdded(admin);
    }

    function removeAdmin(address admin) external onlyAdmin {
        if (admin == msg.sender) revert GandaErrors.Unauthorized();
        if (!_admins[admin]) revert GandaErrors.Unauthorized();
        _admins[admin] = false;
        emit AdminRemoved(admin);
    }

    function isAdmin(address admin) external view returns (bool) {
        return _admins[admin];
    }

    function addWhitelistERC721(address nft) external onlyAdmin {
        if (nft == address(0)) revert GandaErrors.InvalidInput();
        WhitelistEntry storage entry = _whitelistInfo[nft];
        if (entry.active) revert GandaErrors.AlreadyExists();
        entry.active = true;
        entry.index = _whitelist.length;
        _whitelist.push(nft);
        emit WhitelistAdded(nft);
    }

    function removeWhitelist(address nft) external onlyAdmin {
        WhitelistEntry storage entry = _whitelistInfo[nft];
        if (!entry.active) revert GandaErrors.NotFound();
        uint256 index = entry.index;
        uint256 last = _whitelist.length - 1;
        if (index != last) {
            address lastAddr = _whitelist[last];
            _whitelist[index] = lastAddr;
            _whitelistInfo[lastAddr].index = index;
        }
        _whitelist.pop();
        delete _whitelistInfo[nft];
        emit WhitelistRemoved(nft);
    }

    function whitelistCount() external view returns (uint256) {
        return _whitelist.length;
    }

    function whitelistAt(uint256 index) external view returns (address) {
        return _whitelist[index];
    }

    function isWhitelistedHolder(address user) external view returns (bool) {
        if (user == address(0)) return false;
        for (uint256 i = 0; i < _whitelist.length; i++) {
            address nft = _whitelist[i];
            WhitelistEntry memory entry = _whitelistInfo[nft];
            if (!entry.active) continue;
            if (IERC721(nft).balanceOf(user) > 0) return true;
        }
        return false;
    }
}
