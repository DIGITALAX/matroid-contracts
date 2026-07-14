// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {MatroidPaymaster} from "../src/zk/MatroidPaymaster.sol";

contract DeployPaymaster is Script {
    function run() external {
        address governance = vm.envOr("PAYMASTER_GOVERNANCE", address(0));
        uint256 defaultCap = vm.envOr("PAYMASTER_DEFAULT_CAP", uint256(1 ether));
        uint256 fundAmount = vm.envOr("PAYMASTER_FUND", uint256(1 ether));

        address identityRegistry = vm.envOr("IDENTITY_REGISTRY", address(0));
        address kitRegistry = vm.envOr("KIT_REGISTRY", address(0));
        address contentRegistry = vm.envOr("CONTENT_REGISTRY", address(0));
        address kitSignal = vm.envOr("KIT_SIGNAL", address(0));
        address dxCouncil = vm.envOr("DX_COUNCIL", address(0));
        address grantRegistry = vm.envOr("GRANT_REGISTRY", address(0));

        vm.startBroadcast();
        address deployer = msg.sender;
        if (governance == address(0)) governance = deployer;

        MatroidPaymaster paymaster = new MatroidPaymaster(governance, defaultCap);

        address[6] memory targets = [
            identityRegistry,
            kitRegistry,
            contentRegistry,
            kitSignal,
            dxCouncil,
            grantRegistry
        ];
        if (governance == deployer) {
            for (uint256 i = 0; i < targets.length; i++) {
                if (targets[i] != address(0)) {
                    paymaster.setRegistered(targets[i], true);
                }
            }
        } else {
            console2.log(
                "governance != deployer: register the sponsored targets from the governance account"
            );
        }

        if (fundAmount > 0) {
            paymaster.fund{value: fundAmount}();
        }
        vm.stopBroadcast();

        console2.log("MatroidPaymaster:", address(paymaster));
        console2.log("governance:", governance);
        console2.log("defaultCapPerEpoch:", defaultCap);
        console2.log("funded with:", fundAmount);
        console2.log("set NEXT_PUBLIC_PAYMASTER to the address above in dx_app/.env");
    }
}
