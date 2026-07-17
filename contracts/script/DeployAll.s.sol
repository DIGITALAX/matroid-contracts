// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

// matroid
import {StakingFactory} from "../src/StakingFactory.sol";
import {MatroidRegistry} from "../src/MatroidRegistry.sol";
import {MatroidKit} from "../src/MatroidKit.sol";
import {MatroidScorer} from "../src/MatroidScorer.sol";
import {GlobalStakingPool} from "../src/GlobalStakingPool.sol";
import {Treasury} from "../src/Treasury.sol";
import {SlashingCouncil} from "../src/SlashingCouncil.sol";

// dx.app
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


/// One integrated deploy: matroid (real Treasury/Registry/Staking/Governance) +
/// dx.app wired into it as a registered project, sharing ONE MONA.
///
/// Real zk artifacts come from env (POSEIDON, *_VERIFIER, GAS_POOL); when absent
/// they fall back to local stand-ins so the whole thing still runs on plain anvil
/// — only enroll/gasless/balance-snapshot are stubbed, everything else is real.
/// Addresses are kept in storage (not stack) to avoid stack-too-deep.
contract DeployAll is Script {
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
    address public deployer;

    function run() external {
        address poseidon = vm.envOr("POSEIDON", address(0));
        address enrollV = vm.envOr("ENROLLMENT_VERIFIER", address(0));
        address votingV = vm.envOr("VOTING_VERIFIER", address(0));
        address editV = vm.envOr("EDIT_VERIFIER", address(0));
        address actionV = vm.envOr("IDENTITY_ACTION_VERIFIER", address(0));
        address gasPool = vm.envOr("GAS_POOL", address(0));
        address monaEnv = vm.envOr("MONA", address(0));

        vm.startBroadcast();
        (, deployer, ) = vm.readCallers();
        _deployMatroid(monaEnv);
        _createPaymaster();
        _deployDx(poseidon, enrollV, votingV, editV, actionV, gasPool == address(0) ? paymaster : gasPool);
        _wirePaymaster();
        vm.stopBroadcast();

        _writeJson();
    }

    function _createPaymaster() internal {
        uint256 defaultCap = vm.envOr("PAYMASTER_DEFAULT_CAP", uint256(100 ether));
        paymaster = address(new MatroidPaymaster(deployer, defaultCap));
    }

    function _wirePaymaster() internal {
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

    function _deployMatroid(address monaEnv) internal {
        uint256 epochLen = vm.envOr("EPOCH_SECONDS", uint256(7 days));
        uint256 rewardLen = vm.envOr("REWARD_SECONDS", uint256(14 days));
        uint256 voteWin = vm.envOr("VOTING_WINDOW_SECONDS", uint256(3 days));
        uint256 targetLen = vm.envOr("TARGET_DURATION_SECONDS", uint256(4 * 365 days));

        TestMona t = monaEnv == address(0) ? new TestMona() : TestMona(monaEnv);
        mona = address(t);

        StakingFactory factory = new StakingFactory(rewardLen);
        stakingFactory = address(factory);
        MatroidRegistry registry = new MatroidRegistry(mona, address(factory), epochLen, 10, 1000 ether);
        matroidRegistry = address(registry);
        MatroidKit kit = new MatroidKit(address(registry));
        matroidKit = address(kit);
        registry.setMatroidKit(address(kit));
        MatroidScorer sc0 = new MatroidScorer(address(registry), 5e16);
        scorer = address(sc0);
        GlobalStakingPool gpool = new GlobalStakingPool(mona, rewardLen);
        globalStakingPool = address(gpool);
        Treasury tr = new Treasury(
            mona, address(registry), scorer, address(gpool),
            4 * epochLen, 843 ether, targetLen, 4 ether, 1 ether
        );
        treasury = address(tr);
        if (monaEnv == address(0)) {
            t.mint(address(tr), 843 ether);
            t.mint(deployer, 1000 ether);
        }
        SlashingCouncil sc = new SlashingCouncil(mona, address(registry), address(tr), voteWin, 10, 5_000, 6_000);
        slashingCouncil = address(sc);
        tr.setSlashingContract(address(sc));
    }

    function _deployDx(address poseidon, address enrollVerifier, address votingVerifier, address editVerifier, address actionVerifier, address gasPool) internal {
        address enrollX = enrollVerifier == address(0) ? address(new EnrollmentVerifier()) : enrollVerifier;
        address votingX = votingVerifier == address(0) ? address(new VotingVerifier()) : votingVerifier;
        address editX = editVerifier == address(0) ? address(new EditVerifier()) : editVerifier;
        address actionX = actionVerifier == address(0) ? address(new IdentityActionVerifier()) : actionVerifier;
        address gp = gasPool;

        address hasherAddr = poseidon == address(0) ? address(new PoseidonHasher()) : poseidon;

        IdentityRegistry idr = new IdentityRegistry(enrollX, hasherAddr);
        identityRegistry = address(idr);
        identityAction = address(new IdentityAction(actionX, identityRegistry));

        blacklist = address(new Blacklist(msg.sender));
        uint8 initialBucket = uint8(vm.envOr("POOL_INITIAL_BUCKET", uint256(0)));
        uint64 anonWindow = uint64(vm.envOr("ANON_WINDOW_SECONDS", uint256(5 minutes)));
        dxBalancePool = address(new BalancePool(hasherAddr, mona, initialBucket));
        matroidBalancePool = address(new BalancePool(hasherAddr, mona, initialBucket));
        dxCouncil = address(new DxCouncil(actionX, identityRegistry, votingX, dxBalancePool, blacklist, anonWindow, 1, 1));
        matroidAnonGovernance = address(new MatroidAnonGovernance(actionX, identityRegistry, votingX, matroidBalancePool, treasury, paymaster, anonWindow, 1, 1));
        address[] memory dxCouncils = new address[](1);
        dxCouncils[0] = dxCouncil;
        BalancePool(dxBalancePool).setGovernance(dxCouncils);
        address[] memory matroidCouncils = new address[](1);
        matroidCouncils[0] = matroidAnonGovernance;
        BalancePool(matroidBalancePool).setGovernance(matroidCouncils);
        Treasury(treasury).setAnonGovernance(matroidAnonGovernance);

        kitRegistry = address(new KitRegistry(editX, actionX, identityRegistry, blacklist));
        grantRegistry = address(new GrantRegistry(mona, blacklist));
        cyberswagmanRegistry = address(new CyberswagmanRegistry(blacklist));
        sponsorVault = address(new SponsorVault(gp, mona));

        DxProject dxp = new DxProject(mona, matroidKit, matroidRegistry, treasury);
        dxProject = address(dxp);

        prefabMarket = address(new PrefabMarket(mona, sponsorVault, treasury, grantRegistry, cyberswagmanRegistry, 500, 0, blacklist, dxProject));
        contentRegistry = address(new ContentRegistry(editX, actionX, identityRegistry, blacklist));
        kitSignal = address(new KitSignal(actionX, identityRegistry));

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

    function _writeJson() internal {
        string memory json = "deploy-all";
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
        vm.serializeUint(json, "chainId", block.chainid);
        string memory finalJson = vm.serializeAddress(json, "dxProject", dxProject);
        vm.writeJson(finalJson, string.concat("./deployments/all.", vm.toString(block.chainid), ".json"));
    }
}
