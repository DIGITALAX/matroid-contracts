// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMatroidKit {
    function registerProject(string calldata metadata, bool pool) external;
    function matroidIn(address user, address token, uint256 amount) external;
    function matroidOut(address user, address token, uint256 amount) external;
}

interface IMatroidRegistry {
    function setClaimer(address claimer, bool allowed) external;
    function setRewardSplits(
        uint16 globalSplitBps,
        uint16 projectErc20SplitBps,
        uint16 projectNftSplitBps
    ) external;
}

interface ITreasuryClaim {
    function claim(uint256 epoch, address project) external;
}

interface IProjectNFTPool {
    function setNftWeight(address nft, uint256 weight) external;
}

/// dx.app's identity as a project under matroid. This contract IS the registered
/// project: it holds the MONA budget claimed from the matroid Treasury each epoch,
/// and a set of admins can withdraw it. The deployer is the first admin and can
/// add or remove others.
contract DxProject {
    IERC20 public immutable mona;
    IMatroidKit public immutable matroidKit;
    IMatroidRegistry public immutable registry;
    ITreasuryClaim public immutable treasury;

    mapping(address => bool) public admin;
    mapping(address => bool) public router;
    bool public registered;

    event AdminSet(address indexed who, bool isAdmin);
    event RouterSet(address indexed who, bool isRouter);
    event Registered(string metadata, bool pool);
    event ClaimerSet(address indexed claimer, bool allowed);
    event Withdrawn(address indexed to, uint256 amount);

    error NotAdmin();
    error NotRouter();
    error AlreadyRegistered();
    error TransferFailed();

    modifier onlyAdmin() {
        if (!admin[msg.sender]) revert NotAdmin();
        _;
    }

    constructor(
        address monaAddress,
        address matroidKitAddress,
        address registryAddress,
        address treasuryAddress
    ) {
        mona = IERC20(monaAddress);
        matroidKit = IMatroidKit(matroidKitAddress);
        registry = IMatroidRegistry(registryAddress);
        treasury = ITreasuryClaim(treasuryAddress);
        admin[msg.sender] = true;
        emit AdminSet(msg.sender, true);
    }

    /// Registers this contract as a matroid project and authorizes itself as the
    /// claimer of its own budget. Called once, after deploy (registerProject needs
    /// this contract to already have code).
    function register(string calldata metadata, bool pool) external onlyAdmin {
        if (registered) revert AlreadyRegistered();
        registered = true;
        matroidKit.registerProject(metadata, pool);
        registry.setClaimer(address(this), true);
        emit Registered(metadata, pool);
        emit ClaimerSet(address(this), true);
    }

    /// Authorize/deauthorize another address to claim this project's budget.
    function setClaimer(address claimer, bool allowed) external onlyAdmin {
        registry.setClaimer(claimer, allowed);
        emit ClaimerSet(claimer, allowed);
    }

    /// Configure how each claimed epoch budget is split between the global
    /// staking pool, dx.app's ERC20 pool, and dx.app's NFT pool (basis points;
    /// the remainder stays in this contract as the claimer share). The registry
    /// requires msg.sender to be the registered project, hence this passthrough.
    function setRewardSplits(
        uint16 globalSplitBps,
        uint16 projectErc20SplitBps,
        uint16 projectNftSplitBps
    ) external onlyAdmin {
        registry.setRewardSplits(
            globalSplitBps,
            projectErc20SplitBps,
            projectNftSplitBps
        );
    }

    /// Whitelist an NFT collection (or update its weight) on dx.app's NFT
    /// staking pool; the pool requires msg.sender to be the registered project.
    function setNftWeight(
        address pool,
        address nft,
        uint256 weight
    ) external onlyAdmin {
        IProjectNFTPool(pool).setNftWeight(nft, weight);
    }

    /// Pull this project's budget for an epoch; the claimer share lands in this
    /// contract, the rest is routed by the Treasury to any staking pools.
    function claimBudget(uint256 epoch) external {
        treasury.claim(epoch, address(this));
    }

    /// Route a MONA inflow through the matroid kit so it counts as dx.app
    /// activity for the current epoch. The caller must have approved the
    /// MatroidRegistry for `amount`; the registry pulls MONA from the caller
    /// into this contract and records the flow.
    function matroidIn(uint256 amount) external {
        matroidKit.matroidIn(msg.sender, address(mona), amount);
    }

    /// Authorize/deauthorize a dx.app contract (e.g. the PrefabMarket) to
    /// route user payments through this project.
    function setRouter(address who, bool isRouter) external onlyAdmin {
        router[who] = isRouter;
        emit RouterSet(who, isRouter);
    }

    /// Called by an authorized dx.app contract during a sale: records the
    /// buyer's payment as dx.app activity (registry pulls `amount` from `user`
    /// into this contract — the user must have approved the MatroidRegistry)
    /// and forwards it to `to` so the calling contract's accounting is
    /// untouched. This is how dx.app usage becomes matroid activity.
    function routeIn(address user, uint256 amount, address to) external {
        if (!router[msg.sender]) revert NotRouter();
        matroidKit.matroidIn(user, address(mona), amount);
        if (to != address(0)) {
            if (!mona.transfer(to, amount)) revert TransferFailed();
        }
    }

    /// Route a MONA outflow (this contract -> recipient) through the kit,
    /// recorded as dx.app activity. Approves the registry to pull the amount.
    function matroidOut(address to, uint256 amount) external onlyAdmin {
        mona.approve(address(registry), amount);
        matroidKit.matroidOut(to, address(mona), amount);
    }

    function setAdmin(address who, bool isAdmin) external onlyAdmin {
        admin[who] = isAdmin;
        emit AdminSet(who, isAdmin);
    }

    function withdraw(address to, uint256 amount) external onlyAdmin {
        if (!mona.transfer(to, amount)) revert TransferFailed();
        emit Withdrawn(to, amount);
    }
}
