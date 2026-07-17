// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaGames.sol";
import {
    IPaymaster,
    IPaymasterFlow,
    ExecutionResult,
    Transaction,
    PAYMASTER_VALIDATION_SUCCESS_MAGIC,
    BOOTLOADER_FORMAL_ADDRESS
} from "../zk/IPaymasterZk.sol";

contract GandaPaymaster is IPaymaster {
    uint256 public constant EPOCH = 1 days;

    GandaGames public immutable games;
    address public governance;
    uint256 public defaultCapPerEpoch;

    mapping(address => bool) public coreTarget;
    mapping(address => uint256) public gameOfTarget;
    mapping(address => bool) public targetRegistered;
    mapping(address => uint256) public capPerEpoch;
    mapping(address => mapping(uint256 => uint256)) public spentInEpoch;

    event GovernanceTransferred(address indexed previous, address indexed next);
    event CoreTargetSet(address indexed target, bool active);
    event GameTargetRegistered(uint256 indexed gameId, address indexed target, bool active);
    event CapSet(address indexed target, uint256 cap);
    event DefaultCapSet(uint256 cap);
    event Funded(address indexed from, uint256 amount);
    event SponsoredCall(address indexed target, address indexed from, uint256 fee, uint256 epoch);

    modifier onlyBootloader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) revert GandaErrors.Unauthorized();
        _;
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert GandaErrors.Unauthorized();
        _;
    }

    constructor(address gamesAddress, address governanceAddress, uint256 defaultCap) {
        if (gamesAddress == address(0) || governanceAddress == address(0)) {
            revert GandaErrors.ZeroAddress();
        }
        games = GandaGames(gamesAddress);
        governance = governanceAddress;
        defaultCapPerEpoch = defaultCap;
    }

    function transferGovernance(address next) external onlyGovernance {
        if (next == address(0)) revert GandaErrors.ZeroAddress();
        emit GovernanceTransferred(governance, next);
        governance = next;
    }

    function setCoreTarget(address target, bool active) external onlyGovernance {
        if (target == address(0)) revert GandaErrors.ZeroAddress();
        coreTarget[target] = active;
        targetRegistered[target] = active;
        emit CoreTargetSet(target, active);
    }

    function registerGameTarget(uint256 gameId, address target) external {
        if (target == address(0)) revert GandaErrors.ZeroAddress();
        if (!games.isActive(gameId)) revert GandaErrors.GameNotActive();
        if (games.scorerOf(gameId) != msg.sender) revert GandaErrors.NotScorer();
        gameOfTarget[target] = gameId;
        targetRegistered[target] = true;
        emit GameTargetRegistered(gameId, target, true);
    }

    function unregisterGameTarget(address target) external {
        uint256 gameId = gameOfTarget[target];
        if (gameId == 0) revert GandaErrors.NotFound();
        if (games.scorerOf(gameId) != msg.sender && msg.sender != governance) {
            revert GandaErrors.Unauthorized();
        }
        targetRegistered[target] = false;
        gameOfTarget[target] = 0;
        emit GameTargetRegistered(gameId, target, false);
    }

    function setCap(address target, uint256 cap) external onlyGovernance {
        capPerEpoch[target] = cap;
        emit CapSet(target, cap);
    }

    function setDefaultCap(uint256 cap) external onlyGovernance {
        defaultCapPerEpoch = cap;
        emit DefaultCapSet(cap);
    }

    function capOf(address target) public view returns (uint256) {
        uint256 cap = capPerEpoch[target];
        return cap == 0 ? defaultCapPerEpoch : cap;
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

        if (_transaction.paymasterInput.length < 4) revert GandaErrors.InvalidInput();
        if (bytes4(_transaction.paymasterInput[0:4]) != IPaymasterFlow.general.selector) {
            revert GandaErrors.InvalidInput();
        }

        address target = address(uint160(_transaction.to));
        if (!targetRegistered[target]) revert GandaErrors.NotRegistered();
        if (!coreTarget[target]) {
            uint256 gameId = gameOfTarget[target];
            if (gameId == 0 || !games.isActive(gameId)) revert GandaErrors.GameBanned();
        }

        uint256 requiredFee = _transaction.gasLimit * _transaction.maxFeePerGas;
        uint256 epoch = block.timestamp / EPOCH;
        uint256 spent = spentInEpoch[target][epoch] + requiredFee;
        if (spent > capOf(target)) revert GandaErrors.OverEpochLimit();
        spentInEpoch[target][epoch] = spent;

        (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredFee}("");
        if (!success) revert GandaErrors.InvalidInput();

        emit SponsoredCall(target, address(uint160(_transaction.from)), requiredFee, epoch);
        context = abi.encode(target, _transaction.maxFeePerGas, epoch);
    }

    function postTransaction(
        bytes calldata _context,
        Transaction calldata,
        bytes32,
        bytes32,
        ExecutionResult,
        uint256 _maxRefundedGas
    ) external payable onlyBootloader {
        (address target, uint256 maxFeePerGas, uint256 epoch) = abi.decode(_context, (address, uint256, uint256));
        uint256 refund = _maxRefundedGas * maxFeePerGas;
        uint256 spent = spentInEpoch[target][epoch];
        spentInEpoch[target][epoch] = refund >= spent ? 0 : spent - refund;
    }

    function fund() external payable {
        emit Funded(msg.sender, msg.value);
    }

    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
