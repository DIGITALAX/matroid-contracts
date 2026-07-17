// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {MatroidPaymaster} from "../src/zk/MatroidPaymaster.sol";
import {
    Transaction,
    ExecutionResult,
    IPaymasterFlow,
    BOOTLOADER_FORMAL_ADDRESS
} from "../src/zk/IPaymasterZk.sol";

contract MatroidPaymasterTest is Test {
    MatroidPaymaster pm;
    address project = address(0xBEEF);
    address user = address(0xCAFE);

    function setUp() public {
        pm = new MatroidPaymaster(address(this), 100 ether);
        pm.setRegistered(project, true);
        vm.deal(address(pm), 50 ether);
    }

    function _tx(address to, uint256 gasLimit, uint256 maxFeePerGas) internal view returns (Transaction memory t) {
        t.txType = 113;
        t.from = uint256(uint160(user));
        t.to = uint256(uint160(to));
        t.gasLimit = gasLimit;
        t.maxFeePerGas = maxFeePerGas;
        t.paymaster = uint256(uint160(address(pm)));
        t.paymasterInput = abi.encodeWithSelector(IPaymasterFlow.general.selector, bytes(""));
    }

    function _validate(Transaction memory t) internal returns (bytes memory context) {
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        (bytes4 magic, bytes memory ctx) = pm.validateAndPayForPaymasterTransaction(bytes32(0), bytes32(0), t);
        assertEq(magic, pm.validateAndPayForPaymasterTransaction.selector);
        return ctx;
    }

    function testCapCountsActualCostAfterRefund() public {
        uint256 epoch = pm.currentEpoch();
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        bytes memory ctx = _validate(t);

        assertEq(pm.spentInEpoch(project, epoch), 1_000_000 * 1 gwei);

        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        pm.postTransaction(ctx, t, bytes32(0), bytes32(0), ExecutionResult.Success, 900_000);

        assertEq(pm.spentInEpoch(project, epoch), 100_000 * 1 gwei);
    }

    function testSkippedPostStaysPessimistic() public {
        uint256 epoch = pm.currentEpoch();
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        _validate(t);
        assertEq(pm.spentInEpoch(project, epoch), 1_000_000 * 1 gwei);
    }

    function testRefundNeverUnderflows() public {
        uint256 epoch = pm.currentEpoch();
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        bytes memory ctx = _validate(t);

        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        pm.postTransaction(ctx, t, bytes32(0), bytes32(0), ExecutionResult.Success, 2_000_000);

        assertEq(pm.spentInEpoch(project, epoch), 0);
    }

    function testManyRealActionsFitUnderCap() public {
        uint256 epoch = pm.currentEpoch();
        for (uint256 i = 0; i < 50; i++) {
            Transaction memory t = _tx(project, 80_000_000, 1 gwei);
            bytes memory ctx = _validate(t);
            vm.prank(BOOTLOADER_FORMAL_ADDRESS);
            pm.postTransaction(ctx, t, bytes32(0), bytes32(0), ExecutionResult.Success, 79_000_000);
        }
        assertEq(pm.spentInEpoch(project, epoch), 50 * 1_000_000 * 1 gwei);
    }

    function testOverEpochLimitOnDeclaredCeiling() public {
        Transaction memory t = _tx(project, 80_000_000, 2_000 gwei);
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        vm.expectRevert(MatroidPaymaster.OverEpochLimit.selector);
        pm.validateAndPayForPaymasterTransaction(bytes32(0), bytes32(0), t);
    }

    function testNotRegisteredReverts() public {
        Transaction memory t = _tx(address(0xD00D), 1_000_000, 1 gwei);
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        vm.expectRevert(MatroidPaymaster.NotRegistered.selector);
        pm.validateAndPayForPaymasterTransaction(bytes32(0), bytes32(0), t);
    }

    function testBannedReverts() public {
        pm.setBlacklisted(project, true);
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        vm.expectRevert(MatroidPaymaster.ProjectBanned.selector);
        pm.validateAndPayForPaymasterTransaction(bytes32(0), bytes32(0), t);
    }

    function testPostOnlyBootloader() public {
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        bytes memory ctx = _validate(t);
        vm.expectRevert(MatroidPaymaster.OnlyBootloader.selector);
        pm.postTransaction(ctx, t, bytes32(0), bytes32(0), ExecutionResult.Success, 1);
    }

    function testValidateOnlyBootloader() public {
        Transaction memory t = _tx(project, 1_000_000, 1 gwei);
        vm.expectRevert(MatroidPaymaster.OnlyBootloader.selector);
        pm.validateAndPayForPaymasterTransaction(bytes32(0), bytes32(0), t);
    }
}
