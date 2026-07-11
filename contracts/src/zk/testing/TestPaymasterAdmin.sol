// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// Test-only stand-in for IPaymasterAdmin so SponsorCouncil.execute() has a
/// target for Blacklist/Cap proposals on the public anvil deploy.
contract TestPaymasterAdmin {
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public caps;

    event PaymasterBlacklisted(address indexed project, bool banned);
    event PaymasterCapSet(address indexed project, uint256 cap);

    function setBlacklisted(address project, bool banned) external {
        blacklisted[project] = banned;
        emit PaymasterBlacklisted(project, banned);
    }

    function setCap(address project, uint256 cap) external {
        caps[project] = cap;
        emit PaymasterCapSet(project, cap);
    }
}
