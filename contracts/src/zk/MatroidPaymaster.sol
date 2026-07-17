// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {
    IPaymaster,
    IPaymasterFlow,
    ExecutionResult,
    Transaction,
    PAYMASTER_VALIDATION_SUCCESS_MAGIC,
    BOOTLOADER_FORMAL_ADDRESS
} from "./IPaymasterZk.sol";

contract MatroidPaymaster is IPaymaster {
    uint256 public constant EPOCH = 1 days;

    address public governance;
    uint256 public defaultCapPerEpoch;

    mapping(address => bool) public registered;
    mapping(address => bool) public blacklisted;
    mapping(address => uint256) public capPerEpoch;
    mapping(address => mapping(uint256 => uint256)) public spentInEpoch;

    event GovernanceTransferred(address indexed previous, address indexed next);
    event Registered(address indexed project, bool active);
    event BlacklistedSet(address indexed project, bool banned);
    event CapSet(address indexed project, uint256 cap);
    event DefaultCapSet(uint256 cap);
    event Funded(address indexed from, uint256 amount);
    event SponsoredCall(address indexed project, address indexed from, uint256 fee, uint256 epoch);

    error OnlyBootloader();
    error OnlyGovernance();
    error NotRegistered();
    error ProjectBanned();
    error OverEpochLimit();
    error UnsupportedFlow();
    error ShortPaymasterInput();
    error FeeTransferFailed();
    error ZeroAddress();

    modifier onlyBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) revert OnlyBootloader();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    constructor(address governanceAddress, uint256 defaultCap) {
        if (governanceAddress == address(0)) revert ZeroAddress();
        governance = governanceAddress;
        defaultCapPerEpoch = defaultCap;
    }

    function transferGovernance(address next) external onlyGovernance {
        if (next == address(0)) revert ZeroAddress();
        emit GovernanceTransferred(governance, next);
        governance = next;
    }

    function register() external {
        registered[msg.sender] = true;
        emit Registered(msg.sender, true);
    }

    function setRegistered(address project, bool active) external onlyGovernance {
        registered[project] = active;
        emit Registered(project, active);
    }

    function setBlacklisted(address project, bool banned) external onlyGovernance {
        blacklisted[project] = banned;
        emit BlacklistedSet(project, banned);
    }

    function setCap(address project, uint256 cap) external onlyGovernance {
        capPerEpoch[project] = cap;
        emit CapSet(project, cap);
    }

    function setDefaultCap(uint256 cap) external onlyGovernance {
        defaultCapPerEpoch = cap;
        emit DefaultCapSet(cap);
    }

    function capOf(address project) public view returns (uint256) {
        uint256 c = capPerEpoch[project];
        return c == 0 ? defaultCapPerEpoch : c;
    }

    function currentEpoch() public view returns (uint256) {
        return block.timestamp / EPOCH;
    }

    function validateAndPayForPaymasterTransaction(
        bytes32,
        bytes32,
        Transaction calldata _transaction
    ) external payable onlyBootloader returns (bytes4 magic, bytes memory context) {
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;

        if (_transaction.paymasterInput.length < 4) revert ShortPaymasterInput();
        if (bytes4(_transaction.paymasterInput[0:4]) != IPaymasterFlow.general.selector) {
            revert UnsupportedFlow();
        }

        address project = address(uint160(_transaction.to));
        if (!registered[project]) revert NotRegistered();
        if (blacklisted[project]) revert ProjectBanned();

        uint256 requiredFee = _transaction.gasLimit * _transaction.maxFeePerGas;
        uint256 epoch = block.timestamp / EPOCH;
        uint256 spent = spentInEpoch[project][epoch] + requiredFee;
        if (spent > capOf(project)) revert OverEpochLimit();
        spentInEpoch[project][epoch] = spent;

        (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredFee}("");
        if (!success) revert FeeTransferFailed();

        emit SponsoredCall(project, address(uint160(_transaction.from)), requiredFee, epoch);
        context = abi.encode(project, _transaction.maxFeePerGas, epoch);
    }

    function postTransaction(
        bytes calldata _context,
        Transaction calldata,
        bytes32,
        bytes32,
        ExecutionResult,
        uint256 _maxRefundedGas
    ) external payable onlyBootloader {
        (address project, uint256 maxFeePerGas, uint256 epoch) = abi.decode(_context, (address, uint256, uint256));
        uint256 refund = _maxRefundedGas * maxFeePerGas;
        uint256 spent = spentInEpoch[project][epoch];
        spentInEpoch[project][epoch] = refund >= spent ? 0 : spent - refund;
    }

    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
