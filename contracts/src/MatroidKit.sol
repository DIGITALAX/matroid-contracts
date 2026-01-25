// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {MatroidRegistry} from "./MatroidRegistry.sol";
import "./MatroidErrors.sol";

contract MatroidKit {
    MatroidRegistry public immutable registry;

    event ProjectRegistered(address indexed project, bytes32 metadata);
    event MatroidIn(
        address indexed project,
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event MatroidOut(
        address indexed project,
        address indexed user,
        address indexed token,
        uint256 amount
    );

    constructor(address registryAddress) {
        if (registryAddress == address(0)) revert MatroidErrors.ZeroAddress();
        registry = MatroidRegistry(registryAddress);
    }

    function registerProject(bytes32 metadata, bool pool) external {
        registry.registerProject(msg.sender, metadata, pool);
        emit ProjectRegistered(msg.sender, metadata);
    }

    function matroidIn(address user, address token, uint256 amount) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        registry.recordFlow(msg.sender, user, token, amount, true);
        emit MatroidIn(msg.sender, user, token, amount);
    }

    function matroidOut(address user, address token, uint256 amount) external {
        if (user == address(0)) revert MatroidErrors.ZeroAddress();
        if (token == address(0)) revert MatroidErrors.ZeroAddress();
        if (amount == 0) revert MatroidErrors.ZeroAmount();
        registry.recordFlow(msg.sender, user, token, amount, false);
        emit MatroidOut(msg.sender, user, token, amount);
    }
}
