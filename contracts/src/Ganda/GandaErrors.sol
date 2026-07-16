// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

library GandaErrors {
    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error NotFound();
    error AlreadyExists();
    error InvalidInput();
    error GameNotActive();
    error GameBanned();
    error TagBanned();
    error NotScorer();
    error NotGameOwner();
    error BadProof();
    error UnknownRoot();
    error NullifierUsed();
    error BadNonce();
    error InvalidSplit();
    error ProjectNotRegistered();
    error EpochNotClosed();
    error ClaimWindowClosed();
    error NothingToClaim();
    error AlreadyClaimed();
    error NotRegistered();
    error OverEpochLimit();
    error VotingClosed();
    error VotingOpen();
    error QuorumNotMet();
    error AlreadyExecuted();
    error AlreadySet();
}
