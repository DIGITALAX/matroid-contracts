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
import {MatroidGovernance} from "../src/MatroidGovernance.sol";
import {TestERC721} from "./TestERC721.sol";
import {GandaAccessControl} from "../src/Ganda/GandaAccessControl.sol";
import {GandaDesigners} from "../src/Ganda/GandaDesigners.sol";
import {GandaReactionPacks} from "../src/Ganda/GandaReactionPacks.sol";
import {GandaRegistry} from "../src/Ganda/GandaRegistry.sol";
import {GandaErrors} from "../src/Ganda/GandaErrors.sol";
import {KitRegistry} from "../src/zk/KitRegistry.sol";
import {GrantRegistry} from "../src/zk/GrantRegistry.sol";
import {CyberswagmanRegistry} from "../src/zk/CyberswagmanRegistry.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {SponsorVault} from "../src/zk/SponsorVault.sol";
import {SponsorCouncil} from "../src/zk/SponsorCouncil.sol";
import {PrefabMarket} from "../src/zk/PrefabMarket.sol";

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

contract MockVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}

contract MockRoots {
    function isKnownRoot(bytes32) external pure returns (bool) {
        return true;
    }
}

contract MockGasPool {
    function fund() external payable {}
    receive() external payable {}
}

contract MockRootSource {
    bytes32 public root;
    constructor(bytes32 r) {
        root = r;
    }
    function currentRoot() external view returns (bytes32) {
        return root;
    }
}

contract MockPaymasterAdmin {
    address public lastProject;
    bool public lastBanned;
    uint256 public lastCap;
    bool public capCalled;

    function setBlacklisted(address project, bool banned) external {
        lastProject = project;
        lastBanned = banned;
    }

    function setCap(address project, uint256 cap) external {
        lastProject = project;
        lastCap = cap;
        capCalled = true;
    }
}

contract MockSponsorVault {
    uint256 public totalPoints;
    uint256 public rewarded;
    IERC20 public mona;

    constructor(address m) {
        mona = IERC20(m);
    }

    function setPoints(uint256 p) external {
        totalPoints = p;
    }

    function notifyReward(uint256 amount) external {
        mona.transferFrom(msg.sender, address(this), amount);
        rewarded += amount;
    }
}

contract MockTreasuryDeposit {
    uint256 public deposited;
    IERC20 public mona;

    constructor(address m) {
        mona = IERC20(m);
    }

    function deposit(uint256 amount) external {
        mona.transferFrom(msg.sender, address(this), amount);
        deposited += amount;
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

    function testTargetTotalGrowsViaDeposit() public {
        uint256 startTarget = treasury.targetTotal();
        mona.mint(address(this), 1_000 ether);
        treasury.deposit(1_000 ether);
        assertEq(treasury.targetTotal(), startTarget + 1_000 ether);
    }

    function testGovernanceChangesBudgets() public {
        MatroidGovernance gov = new MatroidGovernance(
            address(mona),
            address(treasury),
            VOTING_WINDOW,
            1 ether,
            1000,
            6000
        );
        treasury.setGovernance(address(gov));

        mona.mint(address(this), 1 ether);
        mona.approve(address(gov), type(uint256).max);
        uint256 id = gov.propose(500 ether, 50 ether, 0);

        uint256 big = mona.totalSupply();
        mona.mint(user, big);
        vm.startPrank(user);
        mona.approve(address(gov), type(uint256).max);
        gov.vote(id, true, big);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_WINDOW + 1);
        gov.execute(id);

        assertEq(treasury.baseBudget(), 500 ether);
        assertEq(treasury.perProjectBudget(), 50 ether);
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


    function testDrainStaleToGlobalPool() public {
        vm.startPrank(user);
        mona.approve(address(globalPool), type(uint256).max);
        globalPool.stake(1 ether);
        vm.stopPrank();

        uint256 treasuryBal = mona.balanceOf(address(treasury));
        assertGt(treasuryBal, 0, "treasury funded");

        vm.warp(block.timestamp + 365 days + 1);
        uint256 poolBefore = mona.balanceOf(address(globalPool));
        treasury.drainStale();

        assertEq(mona.balanceOf(address(treasury)), 0, "treasury fully drained");
        assertEq(
            mona.balanceOf(address(globalPool)) - poolBefore,
            treasuryBal,
            "global pool received the stranded funds"
        );
    }

    function testDrainStaleRevertsWhenActive() public {
        vm.expectRevert(MatroidErrors.ClaimNotAvailable.selector);
        treasury.drainStale();
    }

    function testProjectLeaveRemovesEpochContribution() public {
        vm.prank(user);
        project.payIn(10 ether);

        vm.prank(address(project));
        registry.leave();

        vm.warp(block.timestamp + WEEK + 1);
        treasury.finalizeEpoch(0);

        assertEq(scorer.score(address(project), 0), 0, "left project scores zero");
    }

    function testProjectEraseWipesRecord() public {
        vm.prank(address(project));
        registry.eraseSelf();

        MatroidLibrary.Project memory p = registry.getProject(address(project));
        assertEq(p.project, address(0), "record wiped");
        assertEq(p.registered, false, "no longer registered");
    }

    function testGovernanceExtendsDuration() public {
        MatroidGovernance gov = new MatroidGovernance(
            address(mona),
            address(treasury),
            VOTING_WINDOW,
            1 ether,
            1000,
            6000
        );
        treasury.setGovernance(address(gov));

        uint256 newDuration = treasury.targetDuration() + 365 days;

        mona.mint(address(this), 1 ether);
        mona.approve(address(gov), type(uint256).max);
        uint256 id = gov.propose(treasury.baseBudget(), treasury.perProjectBudget(), newDuration);

        uint256 big = mona.totalSupply();
        mona.mint(user, big);
        vm.startPrank(user);
        mona.approve(address(gov), type(uint256).max);
        gov.vote(id, true, big);
        vm.stopPrank();

        vm.warp(block.timestamp + VOTING_WINDOW + 1);
        gov.execute(id);

        assertEq(treasury.targetDuration(), newDuration, "duration extended only up");
    }

    function testChipWeightIncrementsWeighted() public {
        vm.prank(user);
        project.payIn(10 ether);

        MatroidLibrary.EpochStats memory before = registry.getEpochStats(address(project), 0);

        vm.prank(address(kit));
        registry.creditChipWeight(address(project));

        MatroidLibrary.EpochStats memory afterStats = registry.getEpochStats(address(project), 0);
        assertEq(
            afterStats.weightedUniqueUsers,
            before.weightedUniqueUsers + 1,
            "chip credit adds weighted unit"
        );
        assertEq(afterStats.monaUniqueUsers, before.monaUniqueUsers, "raw unique unchanged");
    }

    function testChipVerifiedActivityDoublesWeight() public {
        MockVerifier mv = new MockVerifier();
        MockRoots mr = new MockRoots();
        kit.setVerification(address(mv), address(mr));

        vm.prank(address(project));
        kit.matroidInVerified(
            user,
            address(mona),
            10 ether,
            bytes32(uint256(1)),
            "",
            bytes32(uint256(42))
        );

        MatroidLibrary.EpochStats memory s = registry.getEpochStats(address(project), 0);
        assertEq(s.weightedUniqueUsers, 2, "chip user counts double");
        assertEq(s.monaUniqueUsers, 1, "raw unique is one");
    }

    function testKitAnonymousMode() public {
        MockVerifier pv = new MockVerifier();
        MockVerifier ev = new MockVerifier();
        MockRoots mr = new MockRoots();
        KitRegistry reg = new KitRegistry(address(pv), address(ev), address(mr));

        bytes32 root = bytes32(uint256(1));
        uint256 kitA = reg.publish("", root, bytes32(uint256(10)), bytes32(uint256(0xA1)));
        (, , uint256 parentA, , , , ) = reg.kits(kitA);
        assertEq(parentA, 0, "root kit has no parent");

        uint256 forkB = reg.fork(kitA, "", root, bytes32(uint256(20)), bytes32(uint256(0xB2)));
        (bytes32 ownerB, , uint256 parentB, , , , ) = reg.kits(forkB);
        assertEq(parentB, kitA, "fork tracks its parent");
        assertEq(ownerB, bytes32(uint256(0xB2)), "fork has its own ownerTag");

        reg.pushVersion(kitA, "", bytes32(uint256(11)), 0);
        (, bytes32 designA2, , uint64 verA2, , , ) = reg.kits(kitA);
        assertEq(verA2, 1, "version bumped");
        assertEq(designA2, bytes32(uint256(11)), "design updated");

        reg.remove(kitA, "", 1);
        (, bytes32 designA3, , , , bool revA3, ) = reg.kits(kitA);
        assertEq(designA3, bytes32(0), "content tombstoned");
        assertTrue(revA3, "revoked");
    }

    function testKitPublicMode() public {
        MockVerifier pv = new MockVerifier();
        MockVerifier ev = new MockVerifier();
        MockRoots mr = new MockRoots();
        KitRegistry reg = new KitRegistry(address(pv), address(ev), address(mr));

        address maker = makeAddr("maker");
        vm.prank(maker);
        uint256 id = reg.publishPublic(bytes32(uint256(100)));

        assertEq(reg.ownerOf(id), maker, "public kit is an NFT owned by the maker");

        vm.expectRevert(KitRegistry.NotOwner.selector);
        reg.pushVersionPublic(id, bytes32(uint256(101)));

        vm.prank(maker);
        reg.pushVersionPublic(id, bytes32(uint256(101)));
        (, bytes32 design2, , uint64 ver, , , ) = reg.kits(id);
        assertEq(ver, 1, "version bumped");
        assertEq(design2, bytes32(uint256(101)), "design updated");

        address buyer = makeAddr("buyer");
        vm.prank(maker);
        reg.transferFrom(maker, buyer, id);
        assertEq(reg.ownerOf(id), buyer, "NFT transferred to new owner");

        vm.prank(buyer);
        reg.removePublic(id);
        (, , , , , bool revoked, ) = reg.kits(id);
        assertTrue(revoked, "removed and burned");
    }

    function testKitSignalTallyAndDedup() public {
        MockVerifier sv = new MockVerifier();
        MockRoots mr = new MockRoots();
        KitSignal sig = new KitSignal(address(sv), address(mr));
        bytes32 root = bytes32(uint256(1));

        sig.signal(7, 1, "", root, bytes32(uint256(0x11)));
        sig.signal(7, 1, "", root, bytes32(uint256(0x22)));
        assertEq(sig.tally(7, 1), 2, "two distinct chips signalled up");

        vm.expectRevert(KitSignal.AlreadySignaled.selector);
        sig.signal(7, 1, "", root, bytes32(uint256(0x11)));
    }

    function testSponsorVaultProportionalRewards() public {
        address sa = makeAddr("sponsorA");
        address sb = makeAddr("sponsorB");
        vm.deal(sa, 100 ether);
        vm.deal(sb, 100 ether);

        MockGasPool pool = new MockGasPool();
        MonaMock rewardMona = new MonaMock();
        SponsorVault vault = new SponsorVault(address(pool), address(rewardMona));

        vm.prank(sa);
        vault.deposit{value: 3 ether}();
        vm.prank(sb);
        vault.deposit{value: 1 ether}();

        assertEq(address(pool).balance, 4 ether, "deposits forwarded to gas pool");
        assertEq(vault.totalPoints(), 4 ether, "points equal deposits");

        rewardMona.mint(address(this), 4 ether);
        rewardMona.approve(address(vault), 4 ether);
        vault.notifyReward(4 ether);

        assertEq(vault.pending(sa), 3 ether, "A holds 3/4");
        assertEq(vault.pending(sb), 1 ether, "B holds 1/4");

        vm.prank(sa);
        vault.claim();
        assertEq(rewardMona.balanceOf(sa), 3 ether, "A claimed 3 MONA");

        vm.prank(sb);
        vault.claim();
        assertEq(rewardMona.balanceOf(sb), 1 ether, "B claimed 1 MONA");
    }

    function testSponsorVaultNoSponsorsReverts() public {
        MockGasPool pool = new MockGasPool();
        MonaMock rewardMona = new MonaMock();
        SponsorVault vault = new SponsorVault(address(pool), address(rewardMona));

        rewardMona.mint(address(this), 2 ether);
        rewardMona.approve(address(vault), 2 ether);

        vm.expectRevert(SponsorVault.NoSponsors.selector);
        vault.notifyReward(2 ether);
    }

    function testSponsorVaultLateJoinerNoRetroReward() public {
        address sa = makeAddr("sponsorA");
        address sc = makeAddr("sponsorC");
        vm.deal(sa, 100 ether);
        vm.deal(sc, 100 ether);

        MockGasPool pool = new MockGasPool();
        MonaMock rewardMona = new MonaMock();
        SponsorVault vault = new SponsorVault(address(pool), address(rewardMona));
        rewardMona.mint(address(this), 3 ether);
        rewardMona.approve(address(vault), 3 ether);

        vm.prank(sa);
        vault.deposit{value: 1 ether}();

        vault.notifyReward(1 ether);

        vm.prank(sc);
        vault.deposit{value: 1 ether}();

        assertEq(vault.pending(sa), 1 ether, "A keeps the pre-join reward");
        assertEq(vault.pending(sc), 0, "C earns nothing retroactively");

        vault.notifyReward(2 ether);

        assertEq(vault.pending(sa), 2 ether, "A: 1 old + 1 of new split");
        assertEq(vault.pending(sc), 1 ether, "C: 1 of new split");
    }

    function _newCouncil(MockPaymasterAdmin pm, uint256 quorum_) internal returns (SponsorCouncil) {
        MockVerifier v = new MockVerifier();
        MockRootSource idRoot = new MockRootSource(bytes32(uint256(1)));
        MockRootSource snapRoot = new MockRootSource(bytes32(uint256(2)));
        return new SponsorCouncil(
            address(v), address(idRoot), address(snapRoot), address(pm), 100 ether, 3 days, quorum_, 1
        );
    }

    function testSponsorCouncilBlacklistByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil council = _newCouncil(pm, 2);

        address badProject = address(0xBAD);
        uint256 id = council.proposeBlacklist(badProject, true);

        council.vote("", id, 1, bytes32(uint256(0x1)));
        council.vote("", id, 1, bytes32(uint256(0x2)));

        vm.warp(block.timestamp + 4 days);
        council.execute(id);

        assertEq(pm.lastProject(), badProject, "executed on the project");
        assertTrue(pm.lastBanned(), "banned via vote");
    }

    function testSponsorCouncilCapRaiseByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil council = _newCouncil(pm, 1);

        uint256 id = council.proposeCap(address(0xCAFE), 5 ether);
        council.vote("", id, 1, bytes32(uint256(0xAA)));

        vm.warp(block.timestamp + 4 days);
        council.execute(id);

        assertTrue(pm.capCalled(), "cap was set");
        assertEq(pm.lastProject(), address(0xCAFE), "right project");
        assertEq(pm.lastCap(), 5 ether, "right cap");
    }

    function testSponsorCouncilTieRejected() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil council = _newCouncil(pm, 1);

        uint256 id = council.proposeBlacklist(address(0xBAD), true);
        council.vote("", id, 0, bytes32(uint256(0x1)));
        council.vote("", id, 1, bytes32(uint256(0x2)));

        vm.warp(block.timestamp + 4 days);
        vm.expectRevert(SponsorCouncil.Rejected.selector);
        council.execute(id);
    }

    function testSponsorCouncilDoubleVoteReverts() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil council = _newCouncil(pm, 1);

        uint256 id = council.proposeBlacklist(address(0xBAD), true);
        council.vote("", id, 1, bytes32(uint256(0x1)));
        vm.expectRevert(SponsorCouncil.AlreadyVoted.selector);
        council.vote("", id, 1, bytes32(uint256(0x1)));
    }

    function testSponsorCouncilQuorumAdjustByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil council = _newCouncil(pm, 1);

        uint256 id = council.proposeQuorum(3);
        council.vote("", id, 1, bytes32(uint256(0x1)));

        vm.warp(block.timestamp + 4 days);
        council.execute(id);

        assertEq(council.quorum(), 3, "quorum raised by vote");
    }

    function testSponsorCouncilQuorumBelowFloorReverts() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        MockVerifier v = new MockVerifier();
        MockRootSource idRoot = new MockRootSource(bytes32(uint256(1)));
        MockRootSource snapRoot = new MockRootSource(bytes32(uint256(2)));
        SponsorCouncil council = new SponsorCouncil(
            address(v), address(idRoot), address(snapRoot), address(pm), 100 ether, 3 days, 2, 2
        );

        vm.expectRevert(SponsorCouncil.BelowFloor.selector);
        council.proposeQuorum(1);
    }

    function _newMarket(MonaMock m, uint16 minSlice)
        internal
        returns (PrefabMarket market, MockSponsorVault vault, MockTreasuryDeposit tre)
    {
        vault = new MockSponsorVault(address(m));
        tre = new MockTreasuryDeposit(address(m));
        GrantRegistry grReg = new GrantRegistry(address(m), address(this));
        CyberswagmanRegistry cyReg = new CyberswagmanRegistry(address(m), address(this));
        market = new PrefabMarket(address(m), address(vault), address(tre), address(grReg), address(cyReg), address(this), minSlice, 3000, 30 days);
    }

    function testPrefabDeleteBlockedWhileOpenOrder() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market, MockSponsorVault vault,) = _newMarket(m, 500);
        vault.setPoints(1);

        address fab = makeAddr("fab");
        address buyer = makeAddr("buyer");
        m.mint(buyer, 1000 ether);

        vm.prank(fab);
        uint256 offerId = market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x5417)), address(0));
        vm.stopPrank();

        vm.prank(fab);
        vm.expectRevert(PrefabMarket.HasOpenOrders.selector);
        market.deleteOffer(offerId);

        vm.prank(buyer);
        market.confirmReceipt(orderId);

        assertEq(m.balanceOf(fab), 90 ether, "fabricator paid on confirm");
        assertEq(vault.rewarded(), 10 ether, "slice routed on confirm");

        vm.prank(fab);
        market.deleteOffer(offerId);
    }

    function testPrefabFabricatorCancelFullRefund() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market, MockSponsorVault vault,) = _newMarket(m, 500);
        vault.setPoints(1);

        address fab = makeAddr("fab");
        address buyer = makeAddr("buyer");
        m.mint(buyer, 1000 ether);

        vm.prank(fab);
        uint256 offerId = market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x1)), address(0));
        vm.stopPrank();

        vm.prank(fab);
        market.cancelByFabricator(orderId);

        assertEq(m.balanceOf(buyer), 970 ether, "buyer refunded the 70% escrow");
        assertEq(m.balanceOf(fab), 30 ether, "fabricator keeps the 30% upfront");
        assertEq(vault.rewarded(), 0, "no slice on cancelled order");
    }

    function testPrefabRefundAfterTimeout() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market,,) = _newMarket(m, 500);

        address fab = makeAddr("fab");
        address buyer = makeAddr("buyer");
        m.mint(buyer, 1000 ether);

        vm.prank(fab);
        uint256 offerId = market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x1)), address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        vm.prank(buyer);
        market.refundAfterTimeout(orderId);

        assertEq(m.balanceOf(buyer), 970 ether, "buyer refunded 70% after timeout");
    }

    function testPrefabNoSponsorsSliceToTreasury() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market, MockSponsorVault vault, MockTreasuryDeposit tre) = _newMarket(m, 500);

        address fab = makeAddr("fab");
        address buyer = makeAddr("buyer");
        m.mint(buyer, 1000 ether);

        vm.prank(fab);
        uint256 offerId = market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x1)), address(0));
        vm.stopPrank();

        vm.prank(buyer);
        market.confirmReceipt(orderId);

        assertEq(tre.deposited(), 10 ether, "slice to treasury when no sponsors");
        assertEq(vault.rewarded(), 0, "vault not used");
    }

    function testPrefabSliceTooLow() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market,,) = _newMarket(m, 500);
        address fab = makeAddr("fab");
        vm.prank(fab);
        vm.expectRevert(PrefabMarket.BadSlice.selector);
        market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 400, 5, bytes32(uint256(0xABC)));
    }

    function testPrefabBannedFabricatorCannotCreate() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market,,) = _newMarket(m, 500);
        address fab = makeAddr("fab");

        market.setBlacklisted(fab, true);

        vm.prank(fab);
        vm.expectRevert(PrefabMarket.Banned.selector);
        market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));
    }

    function testSponsorCouncilBanFabricatorByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil councilC = _newCouncil(pm, 1);

        MonaMock m = new MonaMock();
        MockSponsorVault vault = new MockSponsorVault(address(m));
        MockTreasuryDeposit tre = new MockTreasuryDeposit(address(m));
        GrantRegistry grReg = new GrantRegistry(address(m), address(councilC));
        CyberswagmanRegistry cyReg = new CyberswagmanRegistry(address(m), address(councilC));
        PrefabMarket market = new PrefabMarket(
            address(m), address(vault), address(tre), address(grReg), address(cyReg), address(councilC), 500, 3000, 30 days
        );

        address fab = makeAddr("fab");
        uint256 id = councilC.proposeBan(address(market), fab, true);
        councilC.vote("", id, 1, bytes32(uint256(0x1)));
        vm.warp(block.timestamp + 4 days);
        councilC.execute(id);

        assertTrue(market.fabricatorBanned(fab), "fabricator banned by council vote");
    }

    function testPrefabConfirmDeliveryByOracle() public {
        MonaMock m = new MonaMock();
        (PrefabMarket market, MockSponsorVault vault,) = _newMarket(m, 500);
        vault.setPoints(1);

        address fab = makeAddr("fab");
        address buyer = makeAddr("buyer");
        address locker = makeAddr("locker");
        m.mint(buyer, 1000 ether);

        vm.prank(fab);
        uint256 offerId = market.createOffer(1, 0, bytes32(uint256(0xD)), 100 ether, 1000, 5, bytes32(uint256(0xABC)));

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x5417)), locker);
        vm.stopPrank();

        address notLocker = makeAddr("notLocker");
        vm.prank(notLocker);
        vm.expectRevert(PrefabMarket.NotOracle.selector);
        market.confirmDelivery(orderId);

        vm.prank(locker);
        market.confirmDelivery(orderId);

        assertEq(m.balanceOf(fab), 90 ether, "fabricator paid via oracle delivery proof");
        assertEq(vault.rewarded(), 10 ether, "slice routed on delivery");
    }

    function testGrantCreateAndFund() public {
        MonaMock m = new MonaMock();
        GrantRegistry gr = new GrantRegistry(address(m), address(this));

        address creator = makeAddr("creator");
        address treeliner = makeAddr("treeliner");
        m.mint(treeliner, 1000 ether);

        vm.prank(creator);
        uint256 grantId = gr.createGrant(7, bytes32(uint256(0xBEEF)), 500 ether, 1000);

        vm.startPrank(treeliner);
        m.approve(address(gr), 300 ether);
        gr.fundGrant(grantId, 300 ether);
        vm.stopPrank();

        assertEq(m.balanceOf(creator), 300 ether, "funding goes to creator upfront (materials)");
        assertEq(gr.shares(grantId, treeliner), 300 ether, "treeliner earns shares (the score)");

        (, , , , uint256 raised, uint256 totalShares, ) = gr.grants(grantId);
        assertEq(raised, 300 ether, "raised tracked");
        assertEq(totalShares, 300 ether, "total shares tracked");
    }

    function testGrantRewardsByShares() public {
        MonaMock m = new MonaMock();
        GrantRegistry gr = new GrantRegistry(address(m), address(this));

        address creator = makeAddr("creator");
        address ta = makeAddr("treelinerA");
        address tb = makeAddr("treelinerB");
        m.mint(ta, 1000 ether);
        m.mint(tb, 1000 ether);
        m.mint(address(this), 1000 ether);

        vm.prank(creator);
        uint256 grantId = gr.createGrant(7, bytes32(uint256(0xBEEF)), 1000 ether, 1000);

        vm.startPrank(ta);
        m.approve(address(gr), 300 ether);
        gr.fundGrant(grantId, 300 ether);
        vm.stopPrank();

        vm.startPrank(tb);
        m.approve(address(gr), 100 ether);
        gr.fundGrant(grantId, 100 ether);
        vm.stopPrank();

        m.approve(address(gr), 40 ether);
        gr.notifyReward(grantId, 40 ether);

        assertEq(gr.pendingReward(grantId, ta), 30 ether, "A gets 3/4 of the sale slice");
        assertEq(gr.pendingReward(grantId, tb), 10 ether, "B gets 1/4");

        uint256 aBefore = m.balanceOf(ta);
        vm.prank(ta);
        gr.claim(grantId);
        assertEq(m.balanceOf(ta) - aBefore, 30 ether, "A claimed its 30 from the sale");
    }

    function testCouncilBanGrantCreatorByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil councilC = _newCouncil(pm, 1);

        MonaMock m = new MonaMock();
        GrantRegistry gr = new GrantRegistry(address(m), address(councilC));

        address creator = makeAddr("badcreator");
        uint256 id = councilC.proposeBan(address(gr), creator, true);
        councilC.vote("", id, 1, bytes32(uint256(0x1)));
        vm.warp(block.timestamp + 4 days);
        councilC.execute(id);

        assertTrue(gr.creatorBanned(creator), "creator banned by council vote");

        vm.prank(creator);
        vm.expectRevert(GrantRegistry.Banned.selector);
        gr.createGrant(7, bytes32(uint256(0xBEEF)), 500 ether, 1000);
    }

    function testGrantLoopViaPrefab() public {
        MonaMock m = new MonaMock();
        MockSponsorVault vault = new MockSponsorVault(address(m));
        MockTreasuryDeposit tre = new MockTreasuryDeposit(address(m));
        GrantRegistry gr = new GrantRegistry(address(m), address(this));
        CyberswagmanRegistry cyReg = new CyberswagmanRegistry(address(m), address(this));
        PrefabMarket market = new PrefabMarket(
            address(m), address(vault), address(tre), address(gr), address(cyReg), address(this), 500, 3000, 30 days
        );
        vault.setPoints(1);

        address creator = makeAddr("creator");
        address treeliner = makeAddr("treeliner");
        address buyer = makeAddr("buyer");
        m.mint(treeliner, 1000 ether);
        m.mint(buyer, 1000 ether);

        vm.prank(creator);
        uint256 grantId = gr.createGrant(7, bytes32(uint256(0xBEEF)), 500 ether, 1000);

        vm.startPrank(treeliner);
        m.approve(address(gr), 100 ether);
        gr.fundGrant(grantId, 100 ether);
        vm.stopPrank();

        vm.startPrank(creator);
        uint256 offerId = market.createOffer(7, 0, bytes32(uint256(0xD)), 100 ether, 500, 5, bytes32(uint256(0xABC)));
        market.linkGrant(offerId, grantId);
        vm.stopPrank();

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x1)), address(0));
        market.confirmReceipt(orderId);
        vm.stopPrank();

        assertEq(gr.pendingReward(grantId, treeliner), 10 ether, "treeliner earns 10% of the sale through the grant");
    }

    function testCyberswagmanAgentLifecycle() public {
        CyberswagmanRegistry reg = new CyberswagmanRegistry(address(mona), address(this));
        address owner = makeAddr("swagman");

        vm.prank(owner);
        uint256 agentId = reg.registerAgent(bytes32(uint256(0xA1)), bytes32(uint256(0xB2)));
        (address o, bytes32 model, , ) = reg.agents(agentId);
        assertEq(o, owner, "owner set");
        assertEq(model, bytes32(uint256(0xA1)), "model set");

        vm.prank(owner);
        reg.setSchema(agentId, 7, true);
        assertTrue(reg.inSchema(agentId, 7), "kit 7 in schema");
        vm.prank(owner);
        reg.setSchema(agentId, 7, false);
        assertTrue(!reg.inSchema(agentId, 7), "kit 7 removed from schema");

        vm.prank(owner);
        reg.postResult(agentId, 99, bytes32(uint256(0xC3)));
        assertEq(reg.result(agentId, 99), bytes32(uint256(0xC3)), "result posted");

        vm.prank(owner);
        reg.postResult(agentId, 99, bytes32(uint256(0xD4)));
        assertEq(reg.result(agentId, 99), bytes32(uint256(0xD4)), "result is mutable");

        vm.expectRevert(CyberswagmanRegistry.NotOwner.selector);
        reg.updateAgent(agentId, bytes32(uint256(1)), bytes32(uint256(2)));

        vm.prank(owner);
        reg.deleteAgent(agentId);
        (, , , bool exists) = reg.agents(agentId);
        assertTrue(!exists, "agent fully deleted");
    }

    function testCyberswagmanBucketByWeight() public {
        MonaMock m = new MonaMock();
        CyberswagmanRegistry reg = new CyberswagmanRegistry(address(m), address(this));
        m.mint(address(this), 1000 ether);

        address sa = makeAddr("swagA");
        address sb = makeAddr("swagB");

        reg.setWeight(7, sa, 3);
        reg.setWeight(7, sb, 1);

        m.approve(address(reg), 40 ether);
        reg.notifyReward(7, 40 ether);

        assertEq(reg.pendingReward(7, sa), 30 ether, "A gets 3/4 by voted weight");
        assertEq(reg.pendingReward(7, sb), 10 ether, "B gets 1/4 by voted weight");

        vm.prank(sa);
        reg.claim(7);
        assertEq(m.balanceOf(sa), 30 ether, "A claimed 30 from the bucket");
    }

    function testCyberSwagSliceOnSale() public {
        MonaMock m = new MonaMock();
        MockSponsorVault vault = new MockSponsorVault(address(m));
        MockTreasuryDeposit tre = new MockTreasuryDeposit(address(m));
        GrantRegistry gr = new GrantRegistry(address(m), address(this));
        CyberswagmanRegistry cyReg = new CyberswagmanRegistry(address(m), address(this));
        PrefabMarket market = new PrefabMarket(
            address(m), address(vault), address(tre), address(gr), address(cyReg), address(this), 500, 3000, 30 days
        );
        vault.setPoints(1);

        address creator = makeAddr("creator");
        address swagman = makeAddr("swagman");
        address buyer = makeAddr("buyer");
        m.mint(buyer, 1000 ether);

        cyReg.setWeight(7, swagman, 1);

        vm.startPrank(creator);
        uint256 offerId = market.createOffer(7, 0, bytes32(uint256(0xD)), 100 ether, 500, 5, bytes32(uint256(0xABC)));
        market.setCyberSwagBps(offerId, 1000);
        vm.stopPrank();

        vm.startPrank(buyer);
        m.approve(address(market), 100 ether);
        uint256 orderId = market.buy(offerId, bytes32(uint256(0x1)), address(0));
        market.confirmReceipt(orderId);
        vm.stopPrank();

        assertEq(cyReg.pendingReward(7, swagman), 10 ether, "cyberswagman earns 10% of the sale by weight");
    }

    function testCouncilSetsCyberWeightByVote() public {
        MockPaymasterAdmin pm = new MockPaymasterAdmin();
        SponsorCouncil councilC = _newCouncil(pm, 1);

        MonaMock m = new MonaMock();
        CyberswagmanRegistry cyReg = new CyberswagmanRegistry(address(m), address(councilC));

        address swagman = makeAddr("swagman");
        uint256 id = councilC.proposeSetCyberWeight(address(cyReg), 7, swagman, 5);
        councilC.vote("", id, 1, bytes32(uint256(0x1)));
        vm.warp(block.timestamp + 4 days);
        councilC.execute(id);

        assertEq(cyReg.weight(7, swagman), 5, "cyberswagman weight set by council vote");
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
