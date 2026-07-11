// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {MatroidScorer} from "../src/MatroidScorer.sol";
import {Treasury} from "../src/Treasury.sol";
import {GlobalStakingPool} from "../src/GlobalStakingPool.sol";
import {StakingFactory} from "../src/StakingFactory.sol";
import {SlashingCouncil} from "../src/SlashingCouncil.sol";
import {GandaAccessControl} from "../src/Ganda/GandaAccessControl.sol";
import {GandaDesigners} from "../src/Ganda/GandaDesigners.sol";
import {GandaReactionPacks} from "../src/Ganda/GandaReactionPacks.sol";
import {GandaRegistry} from "../src/Ganda/GandaRegistry.sol";

contract MockMona is ERC20 {
    constructor() ERC20("Mock MONA", "MONA") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        MockMona mona = new MockMona();

        uint256 week = 7 days;
        uint256 claimWindow = 4 weeks;
        uint256 votingWindow = 3 days;

        StakingFactory factory = new StakingFactory(2 * week);
        MatroidRegistry registry = new MatroidRegistry(
            address(mona),
            address(factory),
            week,
            10,
            1000 ether
        );
        MatroidKit kit = new MatroidKit(address(registry));
        registry.setMatroidKit(address(kit));

        MatroidScorer scorer = new MatroidScorer(address(registry), 5e16);
        GlobalStakingPool globalPool = new GlobalStakingPool(address(mona), 2 * week);

        Treasury treasury = new Treasury(
            address(mona),
            address(registry),
            address(scorer),
            address(globalPool),
            claimWindow,
            843 ether,
            4 * 365 days,
            4 ether,
            1 ether
        );
        mona.mint(address(treasury), 843 ether);

        SlashingCouncil slashing = new SlashingCouncil(
            address(mona),
            address(registry),
            address(treasury),
            votingWindow,
            10,
            5_000,
            6_000
        );
        treasury.setSlashingContract(address(slashing));

        GandaAccessControl gandaAccess = new GandaAccessControl();
        GandaDesigners gandaDesigners = new GandaDesigners(address(gandaAccess));
        GandaReactionPacks gandaPacks = new GandaReactionPacks(
            address(gandaAccess),
            address(gandaDesigners),
            address(kit),
            address(globalPool),
            10 ether,
            1 ether
        );
        gandaDesigners.setReactionPacks(address(gandaPacks));
        GandaRegistry gandaRegistry = new GandaRegistry(address(gandaAccess), address(gandaPacks));
        gandaPacks.registerProject("ganda");


        vm.stopBroadcast();

        gandaRegistry;
    }
}
