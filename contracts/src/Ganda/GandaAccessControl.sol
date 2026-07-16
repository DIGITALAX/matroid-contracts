// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";

contract GandaAccessControl {
    mapping(address => bool) private _admins;

    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    modifier onlyAdmin() {
        if (!_admins[msg.sender]) revert GandaErrors.Unauthorized();
        _;
    }

    constructor() {
        _admins[msg.sender] = true;
        emit AdminAdded(msg.sender);
    }

    function addAdmin(address admin) external onlyAdmin {
        if (admin == address(0)) revert GandaErrors.ZeroAddress();
        if (_admins[admin]) revert GandaErrors.AlreadyExists();
        _admins[admin] = true;
        emit AdminAdded(admin);
    }

    function removeAdmin(address admin) external onlyAdmin {
        if (!_admins[admin]) revert GandaErrors.NotFound();
        if (admin == msg.sender) revert GandaErrors.InvalidInput();
        _admins[admin] = false;
        emit AdminRemoved(admin);
    }

    function isAdmin(address account) external view returns (bool) {
        return _admins[account];
    }
}
