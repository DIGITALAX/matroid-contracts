// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

struct Transaction {
    uint256 txType;
    uint256 from;
    uint256 to;
    uint256 gasLimit;
    uint256 gasPerPubdataByteLimit;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    uint256 paymaster;
    uint256 nonce;
    uint256 value;
    uint256[4] reserved;
    bytes data;
    bytes signature;
    bytes32[] factoryDeps;
    bytes paymasterInput;
    bytes reservedDynamic;
}

enum ExecutionResult {
    Revert,
    Success
}

address constant BOOTLOADER_FORMAL_ADDRESS = address(0x8001);

interface IPaymasterFlow {
    function general(bytes calldata input) external;

    function approvalBased(
        address _token,
        uint256 _minAllowance,
        bytes calldata _innerInput
    ) external;
}

interface IPaymaster {
    function validateAndPayForPaymasterTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable returns (bytes4 magic, bytes memory context);

    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable;
}

bytes4 constant PAYMASTER_VALIDATION_SUCCESS_MAGIC =
    IPaymaster.validateAndPayForPaymasterTransaction.selector;
