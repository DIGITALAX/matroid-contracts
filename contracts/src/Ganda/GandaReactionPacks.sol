// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import "./GandaErrors.sol";
import "./GandaAccessControl.sol";
import "./GandaLibrary.sol";
import "./GandaDesigners.sol";
import {MatroidKit} from "../MatroidKit.sol";
import {MatroidRegistry} from "../MatroidRegistry.sol";
import {ProjectStakingPool} from "../ProjectStakingPool.sol";
import {ProjectNFTStakingPool} from "../ProjectNFTStakingPool.sol";
import {GlobalStakingPool} from "../GlobalStakingPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract GandaReactionPacks is ERC721Enumerable {
    using SafeERC20 for IERC20;

    GandaAccessControl public accessControl;
    GandaDesigners public designers;
    MatroidKit public matroidKit;
    MatroidRegistry public registry;
    GlobalStakingPool public globalPool;
    IERC20 public mona;
    bool public projectRegistered;

    uint256 private _packCount;
    uint256 private _reactionCount;
    uint256 private _tokenIdCounter;
    uint256 private _purchaseCount;
    uint256 public defaultPriceIncrement;
    uint256 public defaultBasePrice;

    uint256 public constant MAX_RESERVED_SPOTS = 10;
    uint256 public constant MIN_RESERVED_SPOTS = 1;
    uint256 public constant REVENUE_SHARE_PERCENTAGE = 10;
    uint16 public constant GLOBAL_BPS = 2000;
    uint16 public constant PROJECT_BPS = 1000;

    mapping(uint256 => GandaLibrary.ReactionPack) private _reactionPacks;
    mapping(uint256 => GandaLibrary.Reaction) private _reactions;
    mapping(uint256 => GandaLibrary.Purchase) private _purchases;
    mapping(uint256 => uint256[]) private _packPurchases;
    mapping(address => uint256[]) private _buyerPurchases;

    modifier onlyAdmin() {
        if (!accessControl.isAdmin(msg.sender)) revert GandaErrors.Unauthorized();
        _;
    }

    modifier onlyDesigner() {
        if (!designers.isDesigner(msg.sender)) revert GandaErrors.DesignerNotFound();
        _;
    }

    event ReactionPackCreated(
        address indexed designer,
        uint256 indexed packId,
        uint256 basePrice,
        uint256 maxEditions,
        uint256 holderReservedSpots
    );
    event ReactionAdded(
        uint256 indexed packId,
        uint256 indexed reactionId,
        string reactionUri
    );
    event PackPurchased(
        address indexed buyer,
        uint256 indexed purchaseId,
        uint256 indexed packId,
        uint256 price,
        uint256 editionNumber
    );
    event ProjectRegistered(bytes32 metadata);

    constructor(
        address accessControlAddress,
        address designersAddress,
        address matroidKitAddress,
        address globalPoolAddress,
        uint256 defaultBasePriceValue,
        uint256 defaultPriceIncrementValue
    ) ERC721("Reaction Packs", "REACT") {
        accessControl = GandaAccessControl(accessControlAddress);
        designers = GandaDesigners(designersAddress);
        matroidKit = MatroidKit(matroidKitAddress);
        registry = matroidKit.registry();
        globalPool = GlobalStakingPool(globalPoolAddress);
        mona = IERC20(registry.mona());
        defaultBasePrice = defaultBasePriceValue;
        defaultPriceIncrement = defaultPriceIncrementValue;
        _packCount = 0;
        _reactionCount = 0;
        _tokenIdCounter = 0;
        _purchaseCount = 0;

    }

    function registerProject(bytes32 metadata) external onlyAdmin {
        if (projectRegistered) revert GandaErrors.AlreadyExists();
        matroidKit.registerProject(metadata, true);
        registry.setRewardSplits(GLOBAL_BPS, PROJECT_BPS, 0);
        projectRegistered = true;
        emit ProjectRegistered(metadata);
    }

    function createReactionPack(
        uint256 maxEditions,
        uint256 holderReservedSpots,
        string memory packUri,
        string[] memory reactionUris
    ) external onlyDesigner returns (uint256) {
        if (!projectRegistered) revert GandaErrors.ProjectNotRegistered();
        _validatePackCreation(maxEditions, holderReservedSpots, reactionUris);

        uint256 newPackId = _initializeReactionPack(
            maxEditions,
            holderReservedSpots,
            packUri
        );
        _addReactionsToPack(newPackId, reactionUris);
        designers.recordPack(msg.sender, newPackId);

        emit ReactionPackCreated(
            msg.sender,
            newPackId,
            defaultBasePrice,
            maxEditions,
            holderReservedSpots
        );

        return newPackId;
    }

    function _validatePackCreation(
        uint256 maxEditions,
        uint256 holderReservedSpots,
        string[] memory reactionUris
    ) private pure {
        if (
            holderReservedSpots < MIN_RESERVED_SPOTS ||
            holderReservedSpots > MAX_RESERVED_SPOTS
        ) {
            revert GandaErrors.InvalidPrice();
        }
        if (maxEditions == 0 || reactionUris.length == 0) {
            revert GandaErrors.InvalidPrice();
        }
    }

    function _initializeReactionPack(
        uint256 maxEditions,
        uint256 holderReservedSpots,
        string memory packUri
    ) private returns (uint256) {
        _packCount++;
        _reactionPacks[_packCount] = GandaLibrary.ReactionPack({
            designer: msg.sender,
            packId: _packCount,
            currentPrice: defaultBasePrice,
            maxEditions: maxEditions,
            soldCount: 0,
            holderReservedSpots: holderReservedSpots,
            active: true,
            packUri: packUri,
            reactionIds: new uint256[](0),
            buyers: new address[](0),
            buyerShares: new uint256[](0)
        });
        return _packCount;
    }

    function _addReactionsToPack(
        uint256 packId,
        string[] memory reactionUris
    ) private {
        GandaLibrary.ReactionPack storage pack = _reactionPacks[packId];
        for (uint256 i = 0; i < reactionUris.length; i++) {
            _reactionCount++;
            _reactions[_reactionCount] = GandaLibrary.Reaction({
                reactionId: _reactionCount,
                packId: packId,
                reactionUri: reactionUris[i],
                tokenIds: new uint256[](0)
            });
            pack.reactionIds.push(_reactionCount);
            emit ReactionAdded(packId, _reactionCount, reactionUris[i]);
        }
    }

    function purchaseReactionPack(uint256 packId) external {
        if (!projectRegistered) revert GandaErrors.ProjectNotRegistered();
        _validatePurchase(packId);

        uint256 purchasePrice = _reactionPacks[packId].currentPrice;

        (
            address erc20Pool,
            address nftPool,
            uint16 globalSplitBps,
            uint16 projectErc20SplitBps,
            uint16 projectNftSplitBps
        ) = registry.projectRewards(address(this));

        uint256 globalShare = (purchasePrice * globalSplitBps) / 10_000;
        uint256 projectErc20Share = (purchasePrice * projectErc20SplitBps) / 10_000;
        uint256 projectNftShare = (purchasePrice * projectNftSplitBps) / 10_000;
        uint256 signalShare = globalShare + projectErc20Share + projectNftShare;

        _signalInAndStake(msg.sender, signalShare, globalShare, projectErc20Share, projectNftShare, erc20Pool, nftPool);
        _distributeRevenue(_reactionPacks[packId], purchasePrice, msg.sender, signalShare);
        _recordPurchase(packId, purchasePrice);
        _mintReactionTokens(packId);
    }

    function _validatePurchase(uint256 packId) private view {
        GandaLibrary.ReactionPack storage pack = _reactionPacks[packId];
        if (pack.packId == 0) revert GandaErrors.ReactionPackNotFound();
        if (!pack.active) revert GandaErrors.ReactionPackNotActive();
        if (pack.soldCount >= pack.maxEditions) revert GandaErrors.SoldOut();

        if (
            pack.soldCount < pack.holderReservedSpots &&
            !accessControl.isWhitelistedHolder(msg.sender)
        ) {
            revert GandaErrors.NotWhitelistedHolder();
        }

        uint256 purchasePrice = pack.currentPrice;
        if (mona.balanceOf(msg.sender) < purchasePrice) {
            revert GandaErrors.InsufficientBalance();
        }
        if (mona.allowance(msg.sender, address(this)) < purchasePrice) {
            revert GandaErrors.InsufficientBalance();
        }
    }

    function _recordPurchase(uint256 packId, uint256 purchasePrice) private {
        GandaLibrary.ReactionPack storage pack = _reactionPacks[packId];
        pack.soldCount++;
        pack.currentPrice += defaultPriceIncrement;
        pack.buyers.push(msg.sender);

        uint256 shareWeight = _calculateBuyerShare(pack.soldCount);
        pack.buyerShares.push(shareWeight);
        _purchaseCount++;

        _purchases[_purchaseCount] = GandaLibrary.Purchase({
            buyer: msg.sender,
            purchaseId: _purchaseCount,
            packId: packId,
            price: purchasePrice,
            editionNumber: pack.soldCount,
            shareWeight: shareWeight,
            timestamp: block.timestamp
        });

        _packPurchases[packId].push(_purchaseCount);
        _buyerPurchases[msg.sender].push(_purchaseCount);

        emit PackPurchased(
            msg.sender,
            _purchaseCount,
            packId,
            purchasePrice,
            pack.soldCount
        );
    }

    function _mintReactionTokens(uint256 packId) private {
        uint256[] memory reactionIds = _reactionPacks[packId].reactionIds;
        for (uint256 i = 0; i < reactionIds.length; i++) {
            _tokenIdCounter++;
            _mint(msg.sender, _tokenIdCounter);
            _reactions[reactionIds[i]].tokenIds.push(_tokenIdCounter);
        }
    }

    function _signalInAndStake(
        address buyer,
        uint256 signalShare,
        uint256 globalShare,
        uint256 projectErc20Share,
        uint256 projectNftShare,
        address erc20Pool,
        address nftPool
    ) private {
        if (signalShare == 0) return;
        matroidKit.matroidIn(buyer, address(mona), signalShare);
        if (globalShare > 0) {
            mona.forceApprove(address(globalPool), globalShare);
            globalPool.notifyReward(globalShare);
            mona.forceApprove(address(globalPool), 0);
        }

        if (projectErc20Share > 0) {
            if (erc20Pool == address(0)) revert GandaErrors.InvalidInput();
            mona.forceApprove(erc20Pool, projectErc20Share);
            ProjectStakingPool(erc20Pool).notifyRewardToken(address(mona), projectErc20Share);
            mona.forceApprove(erc20Pool, 0);
        }

        if (projectNftShare > 0) {
            if (nftPool == address(0)) revert GandaErrors.InvalidInput();
            mona.forceApprove(nftPool, projectNftShare);
            ProjectNFTStakingPool(nftPool).notifyRewardToken(address(mona), projectNftShare);
            mona.forceApprove(nftPool, 0);
        }
    }

    function _distributeRevenue(
        GandaLibrary.ReactionPack storage pack,
        uint256 price,
        address buyer,
        uint256 signalShare
    ) private {
        uint256 normalShare = price - signalShare;
        if (normalShare == 0) return;

        if (pack.soldCount == 0) {
            mona.safeTransferFrom(buyer, pack.designer, normalShare);
            return;
        }

        uint256 totalShares = 0;
        for (uint256 i = 0; i < pack.buyerShares.length; i++) {
            totalShares += pack.buyerShares[i];
        }

        uint256 designerShare = (normalShare * (100 - REVENUE_SHARE_PERCENTAGE)) / 100;
        uint256 buyerSharePool = normalShare - designerShare;

        mona.safeTransferFrom(buyer, pack.designer, designerShare);

        for (uint256 i = 0; i < pack.buyers.length; i++) {
            uint256 buyerPayout = (buyerSharePool * pack.buyerShares[i]) / totalShares;
            if (buyerPayout > 0) {
                mona.safeTransferFrom(buyer, pack.buyers[i], buyerPayout);
            }
        }
    }

    function _calculateBuyerShare(uint256 editionNumber) private pure returns (uint256) {
        return 100 / editionNumber;
    }

    function getReactionPack(uint256 packId) external view returns (GandaLibrary.ReactionPack memory) {
        return _reactionPacks[packId];
    }

    function getReaction(uint256 reactionId) external view returns (GandaLibrary.Reaction memory) {
        return _reactions[reactionId];
    }

    function getPackCount() external view returns (uint256) {
        return _packCount;
    }

    function getReactionCount() external view returns (uint256) {
        return _reactionCount;
    }

    function getPurchase(uint256 purchaseId) external view returns (GandaLibrary.Purchase memory) {
        return _purchases[purchaseId];
    }

    function getPackPurchases(uint256 packId) external view returns (uint256[] memory) {
        return _packPurchases[packId];
    }

    function getBuyerPurchases(address buyer) external view returns (uint256[] memory) {
        return _buyerPurchases[buyer];
    }

    function getPurchaseCount() external view returns (uint256) {
        return _purchaseCount;
    }

    function setDefaultPrices(uint256 basePrice, uint256 priceIncrement) external onlyAdmin {
        defaultBasePrice = basePrice;
        defaultPriceIncrement = priceIncrement;
    }

    function setAccessControl(address accessControlAddress) external onlyAdmin {
        accessControl = GandaAccessControl(accessControlAddress);
    }

    function setDesigners(address designersAddress) external onlyAdmin {
        designers = GandaDesigners(designersAddress);
    }

    function setGlobalPool(address globalPoolAddress) external onlyAdmin {
        globalPool = GlobalStakingPool(globalPoolAddress);
    }
}
