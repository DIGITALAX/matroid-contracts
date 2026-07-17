// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {StakingFactory} from "../src/StakingFactory.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {MatroidScorer} from "../src/MatroidScorer.sol";
import {GlobalStakingPool} from "../src/GlobalStakingPool.sol";
import {Treasury} from "../src/Treasury.sol";
import {SlashingCouncil} from "../src/SlashingCouncil.sol";

import {KitRegistry} from "../src/zk/KitRegistry.sol";
import {GrantRegistry} from "../src/zk/GrantRegistry.sol";
import {PrefabMarket} from "../src/zk/PrefabMarket.sol";
import {CyberswagmanRegistry} from "../src/zk/CyberswagmanRegistry.sol";
import {SponsorVault} from "../src/zk/SponsorVault.sol";
import {ContentRegistry} from "../src/zk/ContentRegistry.sol";
import {KitSignal} from "../src/zk/KitSignal.sol";
import {Blacklist} from "../src/zk/Blacklist.sol";
import {IdentityRegistry} from "../src/zk/IdentityRegistry.sol";
import {IdentityAction} from "../src/zk/IdentityAction.sol";
import {BalancePool} from "../src/zk/BalancePool.sol";
import {DxCouncil} from "../src/zk/DxCouncil.sol";
import {MatroidAnonGovernance} from "../src/zk/MatroidAnonGovernance.sol";
import {DxProject} from "../src/zk/DxProject.sol";
import {MatroidPaymaster} from "../src/zk/MatroidPaymaster.sol";

import {TestMona} from "../src/zk/testing/TestMona.sol";
import {PoseidonHasher} from "../src/zk/PoseidonHasher.sol";
import {TestNFT} from "../src/zk/testing/TestNFT.sol";
import {MatroidLibrary} from "../src/MatroidLibrary.sol";

import {EditVerifier} from "../src/zk/verifiers/EditVerifier.sol";
import {EnrollmentVerifier} from "../src/zk/verifiers/EnrollmentVerifier.sol";
import {VotingVerifier} from "../src/zk/verifiers/VotingVerifier.sol";
import {IdentityActionVerifier} from "../src/zk/verifiers/IdentityActionVerifier.sol";

/// Same deploy as DeployAll, but split into small phases selected by the STAGE
/// env var. Each stage loads the addresses already deployed from
/// deployments/all.<chainid>.json, deploys its own group, and writes the full
/// map back. If a stage drops mid-run (flaky RPC), re-run ONLY that STAGE.
contract DeployStaged is Script {
    address public mona;
    address public matroidRegistry;
    address public matroidKit;
    address public scorer;
    address public treasury;
    address public globalStakingPool;
    address public stakingFactory;
    address public slashingCouncil;
    address public identityRegistry;
    address public identityAction;
    address public dxBalancePool;
    address public matroidBalancePool;
    address public blacklist;
    address public dxCouncil;
    address public matroidAnonGovernance;
    address public kitRegistry;
    address public grantRegistry;
    address public cyberswagmanRegistry;
    address public sponsorVault;
    address public prefabMarket;
    address public contentRegistry;
    address public kitSignal;
    address public dxProject;
    address public testNft;
    address public paymaster;
    address public enrollVerifier;
    address public votingVerifier;
    address public editVerifier;
    address public actionVerifier;
    address public hasher;
    address public deployer;

    function run() external {
        uint256 stage = vm.envUint("STAGE");
        _load();
        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        if (stage == 1) _stage1();
        else if (stage == 2) _stage2();
        else if (stage == 3) _stage3();
        else if (stage == 4) _stage4();
        else if (stage == 5) _stage5();
        else revert("STAGE must be 1..5");
        vm.stopBroadcast();
        _writeJson();
    }

    // ---- stage 1: matroid base ------------------------------------------------
    function _stage1() internal {
        uint256 epochLen = vm.envOr("EPOCH_SECONDS", uint256(7 days));
        uint256 rewardLen = vm.envOr("REWARD_SECONDS", uint256(14 days));
        uint256 voteWin = vm.envOr("VOTING_WINDOW_SECONDS", uint256(3 days));
        uint256 targetLen = vm.envOr("TARGET_DURATION_SECONDS", uint256(4 * 365 days));

        address monaEnv = vm.envOr("MONA", address(0));
        TestMona t = monaEnv == address(0) ? new TestMona() : TestMona(monaEnv);
        mona = address(t);

        stakingFactory = address(new StakingFactory(rewardLen));
        MatroidRegistry registry = new MatroidRegistry(mona, stakingFactory, epochLen, 10, 1000 ether);
        matroidRegistry = address(registry);
        matroidKit = address(new MatroidKit(matroidRegistry));
        registry.setMatroidKit(matroidKit);
        scorer = address(new MatroidScorer(matroidRegistry, 5e16));
        globalStakingPool = address(new GlobalStakingPool(mona, rewardLen));
        Treasury tr = new Treasury(
            mona, matroidRegistry, scorer, globalStakingPool,
            4 * epochLen, 843 ether, targetLen, 4 ether, 1 ether
        );
        treasury = address(tr);
        if (monaEnv == address(0)) {
            t.mint(treasury, 843 ether);
            t.mint(deployer, 1000 ether);
        }
        slashingCouncil = address(new SlashingCouncil(mona, matroidRegistry, treasury, voteWin, 10, 5_000, 6_000));
        tr.setSlashingContract(slashingCouncil);
    }

    // ---- stage 2: paymaster + verifiers + identity core -----------------------
    function _stage2() internal {
        uint256 defaultCap = vm.envOr("PAYMASTER_DEFAULT_CAP", uint256(100 ether));
        paymaster = address(new MatroidPaymaster(deployer, defaultCap));

        address envEnroll = vm.envOr("ENROLLMENT_VERIFIER", address(0));
        address envVoting = vm.envOr("VOTING_VERIFIER", address(0));
        address envEdit = vm.envOr("EDIT_VERIFIER", address(0));
        address envAction = vm.envOr("IDENTITY_ACTION_VERIFIER", address(0));
        enrollVerifier = envEnroll == address(0) ? address(new EnrollmentVerifier()) : envEnroll;
        votingVerifier = envVoting == address(0) ? address(new VotingVerifier()) : envVoting;
        editVerifier = envEdit == address(0) ? address(new EditVerifier()) : envEdit;
        actionVerifier = envAction == address(0) ? address(new IdentityActionVerifier()) : envAction;

        address poseidon = vm.envOr("POSEIDON", address(0));
        hasher = poseidon == address(0) ? address(new PoseidonHasher()) : poseidon;

        identityRegistry = address(new IdentityRegistry(enrollVerifier, hasher));
        identityAction = address(new IdentityAction(actionVerifier, identityRegistry));
        blacklist = address(new Blacklist(deployer));
    }

    // ---- stage 3: pools + councils + governance wiring ------------------------
    function _stage3() internal {
        uint8 initialBucket = uint8(vm.envOr("POOL_INITIAL_BUCKET", uint256(0)));
        uint64 anonWindow = uint64(vm.envOr("ANON_WINDOW_SECONDS", uint256(5 minutes)));

        dxBalancePool = address(new BalancePool(hasher, mona, initialBucket));
        matroidBalancePool = address(new BalancePool(hasher, mona, initialBucket));
        dxCouncil = address(new DxCouncil(actionVerifier, identityRegistry, votingVerifier, dxBalancePool, blacklist, anonWindow, 1, 1));
        matroidAnonGovernance = address(new MatroidAnonGovernance(actionVerifier, identityRegistry, votingVerifier, matroidBalancePool, treasury, paymaster, anonWindow, 1, 1));

        address[] memory dxCouncils = new address[](1);
        dxCouncils[0] = dxCouncil;
        BalancePool(dxBalancePool).setGovernance(dxCouncils);
        address[] memory matroidCouncils = new address[](1);
        matroidCouncils[0] = matroidAnonGovernance;
        BalancePool(matroidBalancePool).setGovernance(matroidCouncils);
        Treasury(treasury).setAnonGovernance(matroidAnonGovernance);
    }

    // ---- stage 4: dx registries + project + project setup ---------------------
    function _stage4() internal {
        address gasPool = vm.envOr("GAS_POOL", address(0));
        address gp = gasPool == address(0) ? paymaster : gasPool;

        kitRegistry = address(new KitRegistry(editVerifier, actionVerifier, identityRegistry, blacklist));
        grantRegistry = address(new GrantRegistry(mona, blacklist));
        cyberswagmanRegistry = address(new CyberswagmanRegistry(blacklist));
        sponsorVault = address(new SponsorVault(gp, mona));

        DxProject dxp = new DxProject(mona, matroidKit, matroidRegistry, treasury);
        dxProject = address(dxp);

        prefabMarket = address(new PrefabMarket(mona, sponsorVault, treasury, grantRegistry, cyberswagmanRegistry, 500, 0, blacklist, dxProject));
        contentRegistry = address(new ContentRegistry(editVerifier, actionVerifier, identityRegistry, blacklist));
        kitSignal = address(new KitSignal(actionVerifier, identityRegistry));

        Blacklist(blacklist).setSetter(dxCouncil, true);
        Blacklist(blacklist).setSetter(grantRegistry, true);

        dxp.register(
            vm.envOr("DX_METADATA_URI", string("ipfs://QmSZadH1Et2NdDvME7YXHpYTCVwNF1nHLzbf1ht2PrGRAQ")),
            true
        );
        dxp.setRewardSplits(2000, 3000, 1000);
        dxp.setRouter(prefabMarket, true);
        dxp.setClaimer(deployer, true);

        MatroidLibrary.Project memory dxInfo = MatroidRegistry(matroidRegistry).getProject(dxProject);
        TestNFT nft = new TestNFT();
        testNft = address(nft);
        nft.mint(deployer, 3);
        dxp.setNftWeight(dxInfo.projectNftPool, testNft, 100);
    }

    // ---- stage 5: paymaster registration + fund + governance transfer --------
    function _stage5() internal {
        uint256 fundAmount = vm.envOr("PAYMASTER_FUND", uint256(1 ether));
        MatroidPaymaster pm = MatroidPaymaster(payable(paymaster));

        pm.setRegistered(identityRegistry, true);
        pm.setRegistered(kitRegistry, true);
        pm.setRegistered(contentRegistry, true);
        pm.setRegistered(kitSignal, true);
        pm.setRegistered(dxCouncil, true);
        pm.setRegistered(grantRegistry, true);
        pm.setRegistered(matroidAnonGovernance, true);
        pm.setRegistered(dxBalancePool, true);
        pm.setRegistered(matroidBalancePool, true);

        if (fundAmount > 0 && deployer.balance > fundAmount) {
            pm.fund{value: fundAmount}();
        }

        pm.transferGovernance(matroidAnonGovernance);
    }

    // ---- json load / save -----------------------------------------------------
    function _path() internal view returns (string memory) {
        return string.concat("./deployments/all.", vm.toString(block.chainid), ".json");
    }

    function _get(string memory j, string memory k) internal view returns (address) {
        if (vm.keyExistsJson(j, k)) return vm.parseJsonAddress(j, k);
        return address(0);
    }

    function _load() internal {
        string memory p = _path();
        if (!vm.exists(p)) return;
        string memory j = vm.readFile(p);
        mona = _get(j, ".mona");
        matroidRegistry = _get(j, ".matroidRegistry");
        matroidKit = _get(j, ".matroidKit");
        scorer = _get(j, ".scorer");
        treasury = _get(j, ".treasury");
        globalStakingPool = _get(j, ".globalStakingPool");
        stakingFactory = _get(j, ".stakingFactory");
        slashingCouncil = _get(j, ".slashingCouncil");
        identityRegistry = _get(j, ".identityRegistry");
        identityAction = _get(j, ".identityAction");
        dxBalancePool = _get(j, ".dxBalancePool");
        matroidBalancePool = _get(j, ".matroidBalancePool");
        blacklist = _get(j, ".blacklist");
        dxCouncil = _get(j, ".dxCouncil");
        matroidAnonGovernance = _get(j, ".matroidAnonGovernance");
        kitRegistry = _get(j, ".kitRegistry");
        grantRegistry = _get(j, ".grantRegistry");
        cyberswagmanRegistry = _get(j, ".cyberswagmanRegistry");
        sponsorVault = _get(j, ".sponsorVault");
        prefabMarket = _get(j, ".prefabMarket");
        contentRegistry = _get(j, ".contentRegistry");
        kitSignal = _get(j, ".kitSignal");
        dxProject = _get(j, ".dxProject");
        testNft = _get(j, ".testNft");
        paymaster = _get(j, ".paymaster");
        enrollVerifier = _get(j, ".enrollVerifier");
        votingVerifier = _get(j, ".votingVerifier");
        editVerifier = _get(j, ".editVerifier");
        actionVerifier = _get(j, ".actionVerifier");
        hasher = _get(j, ".hasher");
    }

    function _writeJson() internal {
        string memory json = "deploy-staged";
        vm.serializeAddress(json, "mona", mona);
        vm.serializeAddress(json, "matroidRegistry", matroidRegistry);
        vm.serializeAddress(json, "matroidKit", matroidKit);
        vm.serializeAddress(json, "scorer", scorer);
        vm.serializeAddress(json, "treasury", treasury);
        vm.serializeAddress(json, "globalStakingPool", globalStakingPool);
        vm.serializeAddress(json, "stakingFactory", stakingFactory);
        vm.serializeAddress(json, "slashingCouncil", slashingCouncil);
        vm.serializeAddress(json, "identityRegistry", identityRegistry);
        vm.serializeAddress(json, "identityAction", identityAction);
        vm.serializeAddress(json, "dxBalancePool", dxBalancePool);
        vm.serializeAddress(json, "matroidBalancePool", matroidBalancePool);
        vm.serializeAddress(json, "blacklist", blacklist);
        vm.serializeAddress(json, "dxCouncil", dxCouncil);
        vm.serializeAddress(json, "matroidAnonGovernance", matroidAnonGovernance);
        vm.serializeAddress(json, "kitRegistry", kitRegistry);
        vm.serializeAddress(json, "grantRegistry", grantRegistry);
        vm.serializeAddress(json, "cyberswagmanRegistry", cyberswagmanRegistry);
        vm.serializeAddress(json, "sponsorVault", sponsorVault);
        vm.serializeAddress(json, "prefabMarket", prefabMarket);
        vm.serializeAddress(json, "contentRegistry", contentRegistry);
        vm.serializeAddress(json, "kitSignal", kitSignal);
        vm.serializeAddress(json, "testNft", testNft);
        vm.serializeAddress(json, "paymaster", paymaster);
        vm.serializeAddress(json, "enrollVerifier", enrollVerifier);
        vm.serializeAddress(json, "votingVerifier", votingVerifier);
        vm.serializeAddress(json, "editVerifier", editVerifier);
        vm.serializeAddress(json, "actionVerifier", actionVerifier);
        vm.serializeAddress(json, "hasher", hasher);
        vm.serializeUint(json, "chainId", block.chainid);
        string memory finalJson = vm.serializeAddress(json, "dxProject", dxProject);
        vm.writeJson(finalJson, _path());
    }
}
