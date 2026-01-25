// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

contract MatroidErrors {
    error ZeroAmount();
    error ZeroAddress();
    error NotOwner();
    error NotMatroidKit();
    error AlreadyRegistered();
    error AlreadySet();
    error ProjectNotRegistered();
    error NotContract();
    error NotClaimer();
    error NotTreasury();
    error MinStakeNotMet();
    error ClaimNotAvailable();
    error EpochNotFinalized();
    error InvalidDuration();
    error InvalidSplit();
    error PoolNotSet();
    error NotSlashing();
    error VoteWindowClosed();
    error InvalidSlash();
    error NotProject();
    error TokenDisabled();
    error TokenExists();
    error TokenInUse();
    error InsufficientStake();
    error ProjectBlacklisted();
    error NotWhitelistedNFT();
    error NotNFTOwner();
    error NFTAlreadyStaked();
    error NFTNotStaked();
}
