// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

contract GandaErrors {
    error Unauthorized();
    error AlreadyExists();
    error NotFound();
    error NotActive();
    error InvalidInput();
    error InvalidPrice();
    error SoldOut();
    error InsufficientBalance();
    error DesignerNotFound();
    error DesignerNotActive();
    error OnlyInviter();
    error ReactionPackNotFound();
    error ReactionPackNotActive();
    error NotWhitelistedHolder();
    error ProjectNotRegistered();
}
