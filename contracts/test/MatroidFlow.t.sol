// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {MatroidScorer} from "../src/MatroidScorer.sol";
import {Treasury} from "../src/Treasury.sol";
import {TestProject} from "./TestProject.sol";
import {MatroidLibrary} from "../src/MatroidLibrary.sol";
import {GandaLibrary} from "../src/Ganda/GandaLibrary.sol";
import {MatroidErrors} from "../src/MatroidErrors.sol";
import {GlobalStakingPool} from "../src/GlobalStakingPool.sol";
import {ProjectStakingPool} from "../src/ProjectStakingPool.sol";
import {ProjectNFTStakingPool} from "../src/ProjectNFTStakingPool.sol";
import {StakingFactory} from "../src/StakingFactory.sol";
import {SlashingCouncil} from "../src/SlashingCouncil.sol";
import {TestERC721} from "./TestERC721.sol";
import {GandaAccessControl} from "../src/Ganda/GandaAccessControl.sol";
import {GandaDesigners} from "../src/Ganda/GandaDesigners.sol";
import {GandaReactionPacks} from "../src/Ganda/GandaReactionPacks.sol";
import {GandaRegistry} from "../src/Ganda/GandaRegistry.sol";
import {GandaErrors} from "../src/Ganda/GandaErrors.sol";

contract MonaMock is IERC20 {
    string public name = "MONA";
    string public symbol = "MONA";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MatroidFlowTest is Test {
    MonaMock internal mona;
    MonaMock internal otherToken;
    MatroidRegistry internal registry;
    MatroidKit internal kit;
    MatroidScorer internal scorer;
    Treasury internal treasury;
    TestProject internal project;
    GlobalStakingPool internal globalPool;
    StakingFactory internal factory;
    SlashingCouncil internal slashing;
    TestERC721 internal nft;
    GandaAccessControl internal gandaAccess;
    GandaDesigners internal gandaDesigners;
    GandaReactionPacks internal gandaPacks;
    GandaRegistry internal gandaRegistry;

    address internal user = address(0xBEEF);
    address internal user2 = address(0xD00D);
    address internal claimer = address(0xCAFE);

    uint256 internal constant WEEK = 7 days;
    uint256 internal constant CLAIM_WINDOW = 4 weeks;
    uint256 internal constant VOTING_WINDOW = 3 days;

    function setUp() public {
        mona = new MonaMock();
        otherToken = new MonaMock();
        factory = new StakingFactory(2 * WEEK);
        registry = new MatroidRegistry(address(mona), address(factory), WEEK, 10, 1000 ether);
        kit = new MatroidKit(address(registry));
        registry.setMatroidKit(address(kit));
        scorer = new MatroidScorer(address(registry), 5e16);
        globalPool = new GlobalStakingPool(address(mona), 2 * WEEK);
        treasury = new Treasury(
            address(mona),
            address(registry),
            address(scorer),
            address(globalPool),
            CLAIM_WINDOW,
            1_000_000 ether,
            4 * 365 days,
            100 ether,
            10 ether
        );
        slashing = new SlashingCouncil(
            address(mona),
            address(registry),
            address(treasury),
            VOTING_WINDOW,
            10,
            5_000,
            6_000
        );
        treasury.setSlashingContract(address(slashing));
        project = new TestProject(address(mona), address(kit));
        nft = new TestERC721();
        gandaAccess = new GandaAccessControl();
        gandaDesigners = new GandaDesigners(address(gandaAccess));
        gandaPacks = new GandaReactionPacks(
            address(gandaAccess),
            address(gandaDesigners),
            address(kit),
            address(globalPool),
            10 ether,
            1 ether
        );
        gandaDesigners.setReactionPacks(address(gandaPacks));
        gandaRegistry = new GandaRegistry(address(gandaAccess), address(gandaPacks));

        mona.mint(user, 1_000 ether);
        mona.mint(user2, 1_000 ether);
        mona.mint(address(project), 1_000 ether);
        mona.mint(address(this), 1_000 ether);
        otherToken.mint(user, 1_000 ether);
        otherToken.mint(address(project), 1_000 ether);
        nft.mint(user, 1);
        nft.mint(user2, 1);
        gandaAccess.addWhitelistERC721(address(nft));

        project.register(bytes32("demo"), false);
        project.setClaimer(claimer, true);

        vm.startPrank(user);
        mona.approve(address(registry), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(user2);
        mona.approve(address(registry), type(uint256).max);
        vm.stopPrank();

        project.approveRegistry(address(mona), address(registry), type(uint256).max);
        project.approveRegistry(address(otherToken), address(registry), type(uint256).max);

        mona.approve(address(treasury), type(uint256).max);
        treasury.deposit(500 ether);
    }

    function testWeeklyFlowClaim() public {
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);

        treasury.finalizeEpoch(0);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        uint256 before = mona.balanceOf(claimer);
        vm.prank(claimer);
        treasury.claim(0, address(project));
        uint256 afterBal = mona.balanceOf(claimer);

        assertGt(afterBal, before, "claimer should receive payout");
    }

    function testClaimExpiresAfterWindow() public {
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + CLAIM_WINDOW + 1);

        treasury.finalizeEpoch(0);

        vm.prank(claimer);
        vm.expectRevert();
        treasury.claim(0, address(project));
    }

    function testSweepExpiredClearsClaimable() public {
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        treasury.computeClaimable(0, address(project));
        assertGt(treasury.claimable(0, address(project)), 0, "claimable should exist");

        vm.warp(block.timestamp + CLAIM_WINDOW + 1);
        treasury.sweepExpired(0, address(project));
        assertEq(treasury.claimable(0, address(project)), 0, "claimable should clear");
    }

    function testMultiProjectDistribution() public {
        TestProject projectB = new TestProject(address(mona), address(kit));
        address claimerB = address(0xB0B);
        projectB.register(bytes32("demo-b"), false);
        projectB.setClaimer(claimerB, true);
        projectB.approveRegistry(address(mona), address(registry), type(uint256).max);

        vm.prank(user);
        project.payIn(5 ether);

        vm.prank(user);
        projectB.payIn(20 ether);
        vm.prank(user2);
        projectB.payIn(5 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        treasury.computeClaimable(0, address(project));
        treasury.computeClaimable(0, address(projectB));

        uint256 claimA = treasury.claimable(0, address(project));
        uint256 claimB = treasury.claimable(0, address(projectB));
        assertGt(claimB, claimA, "higher activity should yield higher claimable");
    }

    function testVotingWindowStartsOnFinalize() public {
        vm.prank(user);
        project.payIn(1 ether);

        vm.warp(block.timestamp + WEEK + VOTING_WINDOW + 1);
        treasury.finalizeEpoch(0);

        vm.warp(block.timestamp + 1);
        vm.startPrank(user);
        mona.approve(address(slashing), type(uint256).max);
        slashing.vote(0, address(project), 1 ether, 1_000, false);
        vm.stopPrank();
    }

    function testGlobalRewardsSmallAmountDistributes() public {
        vm.startPrank(user);
        mona.approve(address(globalPool), type(uint256).max);
        globalPool.stake(1 ether);
        vm.stopPrank();

        mona.approve(address(globalPool), 1);
        globalPool.notifyReward(1);

        vm.warp(block.timestamp + 2 * WEEK + 1);

        uint256 before = mona.balanceOf(user);
        vm.prank(user);
        globalPool.claim();
        uint256 afterBal = mona.balanceOf(user);

        assertEq(afterBal - before, 0, "small reward should stay queued");
        assertEq(globalPool.queuedRewards(), 1, "small reward should remain queued");
    }

    function testProjectNftPoolStakeAndClaim() public {
        project.createProjectPool();
        project.setProjectNftWeight(address(nft), 10 ether);

        ( , address nftPoolAddr,,,) = registry.projectRewards(address(project));
        ProjectNFTStakingPool nftPool = ProjectNFTStakingPool(nftPoolAddr);

        vm.startPrank(user);
        nft.approve(address(nftPool), 1);
        nftPool.stakeNFT(address(nft), 1);
        vm.stopPrank();

        mona.approve(address(nftPool), 100 ether);
        nftPool.notifyRewardToken(address(mona), 100 ether);

        vm.warp(block.timestamp + 2 * WEEK + 1);

        uint256 before = mona.balanceOf(user);
        vm.prank(user);
        nftPool.claim(address(mona));
        uint256 afterBal = mona.balanceOf(user);

        assertGt(afterBal, before, "nft staker should receive rewards");
    }

    function testProjectNftPoolRejectsUnwhitelisted() public {
        project.createProjectPool();

        ( , address nftPoolAddr,,,) = registry.projectRewards(address(project));
        ProjectNFTStakingPool nftPool = ProjectNFTStakingPool(nftPoolAddr);

        vm.startPrank(user);
        nft.approve(address(nftPool), 1);
        vm.expectRevert(MatroidErrors.NotWhitelistedNFT.selector);
        nftPool.stakeNFT(address(nft), 1);
        vm.stopPrank();
    }

    function testGandaRegisterAndPurchasePack() public {
        gandaPacks.registerProject(bytes32("ganda-project"));
        gandaDesigners.inviteDesigner(user);

        vm.startPrank(user);
        string[] memory reactions = new string[](1);
        reactions[0] = "ipfs://reaction";
        uint256 packId = gandaPacks.createReactionPack(5, 1, "ipfs://pack", reactions);
        mona.approve(address(gandaPacks), type(uint256).max);
        gandaPacks.purchaseReactionPack(packId);
        vm.stopPrank();

        GandaLibrary.ReactionPack memory pack = gandaPacks.getReactionPack(packId);
        assertEq(pack.soldCount, 1, "pack should be sold once");
    }

    function testGandaRegisterAndSubmitReaction() public {
        gandaPacks.registerProject(bytes32("ganda-project"));
        uint256 gandaId = gandaRegistry.registerGanda(user, "ipfs://ganda");

        gandaDesigners.inviteDesigner(user);
        vm.startPrank(user);
        string[] memory reactions = new string[](1);
        reactions[0] = "ipfs://reaction";
        uint256 packId = gandaPacks.createReactionPack(5, 1, "ipfs://pack", reactions);
        mona.approve(address(gandaPacks), type(uint256).max);
        gandaPacks.purchaseReactionPack(packId);
        vm.stopPrank();

        GandaLibrary.ReactionUsage[] memory usage = new GandaLibrary.ReactionUsage[](1);
        usage[0] = GandaLibrary.ReactionUsage({reactionId: 1, count: 1});

        vm.prank(user);
        gandaRegistry.submitReaction(gandaId, "ipfs://review", usage);

        GandaLibrary.Ganda memory ganda = gandaRegistry.getGanda(gandaId);
        assertEq(ganda.reactionCount, 1, "ganda reaction count should increase");
    }

    function testGandaPurchaseRequiresRegistration() public {
        gandaDesigners.inviteDesigner(user);
        vm.startPrank(user);
        string[] memory reactions = new string[](1);
        reactions[0] = "ipfs://reaction";
        vm.expectRevert(GandaErrors.ProjectNotRegistered.selector);
        gandaPacks.createReactionPack(5, 1, "ipfs://pack", reactions);
        vm.stopPrank();
    }

    function testTokenDiversityBonus() public {
        TestProject projectB = new TestProject(address(mona), address(kit));
        projectB.register(bytes32("demo-b"), false);
        projectB.setClaimer(address(0xB0B), true);
        projectB.approveRegistry(address(mona), address(registry), type(uint256).max);
        projectB.approveRegistry(address(otherToken), address(registry), type(uint256).max);

        vm.prank(user);
        project.payIn(10 ether);

        vm.prank(user);
        projectB.payIn(10 ether);

        vm.startPrank(user);
        otherToken.approve(address(registry), type(uint256).max);
        vm.stopPrank();

        vm.prank(address(project));
        kit.matroidIn(user, address(otherToken), 1 ether);

        for (uint256 i = 0; i < 10; i++) {
            address wallet = vm.addr(i + 1);
            otherToken.mint(wallet, 10 ether);
            vm.startPrank(wallet);
            otherToken.approve(address(registry), type(uint256).max);
            vm.stopPrank();

            vm.prank(address(projectB));
            kit.matroidIn(wallet, address(otherToken), 1 ether);
        }

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        uint256 scoreA = scorer.score(address(project), 0);
        uint256 scoreB = scorer.score(address(projectB), 0);
        assertGt(scoreB, scoreA, "other token activity should boost score");
    }

    function testRecurringWalletsCount() public {
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);

        vm.prank(user);
        project.payIn(5 ether);

        MatroidLibrary.EpochStats memory stats = registry.getEpochStats(address(project), 1);
        assertEq(stats.monaRecurringUsers, 1, "recurring user should be counted");
    }

    function testTargetTotalAndDurationUpdates() public {
        uint256 startTarget = treasury.targetTotal();
        treasury.setTargetTotal(startTarget + 1_000 ether);
        assertEq(treasury.targetTotal(), startTarget + 1_000 ether);

        uint256 startDuration = treasury.targetDuration();
        treasury.setTargetDuration(startDuration + 30 days);
        assertEq(treasury.targetDuration(), startDuration + 30 days);
    }

    function testRewardSplitsAndPools() public {
        project.createProjectPool();
        project.setRewardSplits(2000, 3000, 0);

        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        uint256 globalBefore = mona.balanceOf(address(globalPool));
        (address pool,,, ,) = registry.projectRewards(address(project));
        uint256 projectBefore = mona.balanceOf(pool);

        vm.prank(claimer);
        treasury.claim(0, address(project));

        assertGt(mona.balanceOf(address(globalPool)), globalBefore, "global pool should receive rewards");
        assertGt(mona.balanceOf(pool), projectBefore, "project pool should receive rewards");
    }

    function testProjectPoolExtraTokenRewards() public {
        project.createProjectPool();
        (address pool,,, ,) = registry.projectRewards(address(project));
        ProjectStakingPool projectPool = ProjectStakingPool(pool);

        vm.prank(address(project));
        projectPool.addRewardToken(address(otherToken));
        otherToken.mint(address(this), 100 ether);
        otherToken.approve(address(projectPool), type(uint256).max);
        projectPool.notifyRewardToken(address(otherToken), 50 ether);

        mona.approve(address(projectPool), type(uint256).max);
        projectPool.stake(10 ether);
        vm.warp(block.timestamp + WEEK);
        projectPool.claim(address(otherToken));

        assertGt(otherToken.balanceOf(address(this)), 50 ether, "staker should receive extra token rewards");
    }

    function testSlashingReducesClaim() public {
        project.createProjectPool();
        project.setRewardSplits(0, 0, 0);

        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);

        _stakeAndVote(0, address(project), 3000, false);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        treasury.computeClaimable(0, address(project));
        uint256 expected = treasury.claimable(0, address(project));

        uint256 before = mona.balanceOf(claimer);
        vm.prank(claimer);
        treasury.claim(0, address(project));
        uint256 afterBal = mona.balanceOf(claimer);

        uint256 received = afterBal - before;
        uint256 slashed = (expected * 3000) / 10_000;
        assertEq(received, expected - slashed, "slashed project should receive reduced payout");
        assertGt(expected, 0, "claimable should exist before slashing");
    }

    function testBlacklistBlocksClaim() public {
        project.setRewardSplits(0, 0, 0);
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);

        _stakeAndVote(0, address(project), 5000, true);
        vm.warp(block.timestamp + VOTING_WINDOW + 1);

        uint256 before = mona.balanceOf(claimer);
        vm.prank(claimer);
        treasury.claim(0, address(project));
        uint256 afterBal = mona.balanceOf(claimer);
        assertEq(afterBal, before, "blacklisted project should not receive payout");
    }

    function testSlashFailureSlashesVotersAndRewardsProject() public {
        project.setRewardSplits(0, 0, 0);
        vm.prank(user);
        project.payIn(10 ether);

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);

        address voter1 = address(0x1111);
        address voter2 = address(0x2222);

        mona.mint(voter1, 1000 ether);
        mona.mint(voter2, 1000 ether);

        vm.startPrank(voter1);
        mona.approve(address(slashing), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(voter2);
        mona.approve(address(slashing), type(uint256).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(voter1);
        slashing.vote(0, address(project), 1000 ether, 3000, false);
        vm.prank(voter2);
        slashing.vote(0, address(project), 1000 ether, 3000, false);

        treasury.computeClaimable(0, address(project));
        uint256 baseClaim = treasury.claimable(0, address(project));

        vm.warp(block.timestamp + VOTING_WINDOW + 1);
        uint256 treasuryBefore = mona.balanceOf(address(treasury));
        slashing.resolveFailure(0, address(project));
        uint256 treasuryAfter = mona.balanceOf(address(treasury));

        assertEq(
            slashing.lockedStake(0, address(project), voter1),
            900 ether,
            "voter1 should be slashed 10%"
        );
        assertEq(
            slashing.lockedStake(0, address(project), voter2),
            900 ether,
            "voter2 should be slashed 10%"
        );
        assertEq(treasuryAfter - treasuryBefore, 200 ether, "treasury should receive total slashed");
        uint256 reward = treasury.slashRewards(0, address(project));
        assertEq(reward, 100 ether, "project reward should be half");

        uint256 before = mona.balanceOf(claimer);
        vm.prank(claimer);
        treasury.claim(0, address(project));
        uint256 afterBal = mona.balanceOf(claimer);
        assertEq(afterBal - before, baseClaim + reward, "project should receive base claim plus reward");
    }

    function _stakeAndVote(uint256 epoch, address target, uint16 slashBps, bool blacklist) internal {
        address voter1 = address(0x1111);
        address voter2 = address(0x2222);
        address voter3 = address(0x3333);

        mona.mint(voter1, 1000 ether);
        mona.mint(voter2, 1000 ether);
        mona.mint(voter3, 1000 ether);

        vm.startPrank(voter1);
        mona.approve(address(slashing), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(voter2);
        mona.approve(address(slashing), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(voter3);
        mona.approve(address(slashing), type(uint256).max);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(voter1);
        slashing.vote(epoch, target, 1000 ether, slashBps, blacklist);
        vm.prank(voter2);
        slashing.vote(epoch, target, 1000 ether, slashBps, blacklist);
        vm.prank(voter3);
        slashing.vote(epoch, target, 1000 ether, slashBps, blacklist);
    }
}
