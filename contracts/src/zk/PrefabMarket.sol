// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISponsorVault {
    function totalPoints() external view returns (uint256);
    function notifyReward(uint256 amount) external;
}

interface ITreasuryDeposit {
    function deposit(uint256 amount) external;
}

interface IGrantRegistry {
    function salesShareBps(uint256 grantId) external view returns (uint16);
    function totalSharesOf(uint256 grantId) external view returns (uint256);
    function notifyReward(uint256 grantId, uint256 amount) external;
}

interface ICyberRegistry {
    function totalWeight(uint256 projectId) external view returns (uint256);
    function notifyReward(uint256 projectId, uint256 amount) external;
}

contract PrefabMarket {
    uint16 public constant BPS = 10000;

    IERC20 public immutable mona;
    ISponsorVault public immutable sponsorVault;
    ITreasuryDeposit public immutable treasury;
    IGrantRegistry public immutable grantRegistry;
    ICyberRegistry public immutable cyberRegistry;
    address public immutable council;
    uint16 public immutable minSliceBps;
    uint16 public immutable upfrontBps;
    uint64 public immutable fulfillWindow;

    struct Offer {
        address fabricator;
        uint256 kitId;
        uint64 version;
        bytes32 designHash;
        string contentUri;
        uint256 price;
        uint16 sliceBps;
        uint256 quantity;
        bytes32 pubkey;
        bool exists;
        uint256 openOrders;
        uint256 grantId;
        uint16 grantBps;
        bool grantLinked;
        uint16 cyberSwagBps;
    }

    struct Order {
        uint256 offerId;
        address buyer;
        address oracle;
        uint256 escrowAmount;
        uint256 slice;
        uint256 grantId;
        uint256 grantSlice;
        uint256 cyberSlice;
        bytes32 shippingCommitment;
        uint64 deadline;
        bool open;
    }

    mapping(uint256 => Offer) public offers;
    uint256 public offerCount;
    mapping(uint256 => Order) public orders;
    uint256 public orderCount;
    mapping(address => bool) public fabricatorBanned;

    event OfferCreated(uint256 indexed offerId, address indexed fabricator, uint256 kitId, uint64 version, bytes32 designHash, string contentUri, uint256 price, uint16 sliceBps, uint256 quantity);
    event OfferUpdated(uint256 indexed offerId, uint256 price, uint16 sliceBps, uint256 quantity);
    event OfferDeleted(uint256 indexed offerId);
    event GrantLinked(uint256 indexed offerId, uint256 indexed grantId, uint16 grantBps);
    event CyberSwagSet(uint256 indexed offerId, uint16 cyberSwagBps);
    event OrderPlaced(uint256 indexed orderId, uint256 indexed offerId, address indexed buyer, address oracle, bytes32 shippingCommitment);
    event OrderReleased(uint256 indexed orderId, bool byOracle);
    event OrderRefunded(uint256 indexed orderId);
    event FabricatorBanned(address indexed fabricator, bool banned);

    error NotFabricator();
    error NotCouncil();
    error NoOffer();
    error BadSlice();
    error SoldOut();
    error HasOpenOrders();
    error OrderClosed();
    error NotBuyer();
    error NotOracle();
    error TooEarly();
    error Banned();
    error NoFunders();
    error SharesExceedEscrow();
    error TransferFailed();

    constructor(
        address monaAddress,
        address sponsorVaultAddress,
        address treasuryAddress,
        address grantRegistryAddress,
        address cyberRegistryAddress,
        address councilAddress,
        uint16 minSliceBps_,
        uint16 upfrontBps_,
        uint64 fulfillWindow_
    ) {
        mona = IERC20(monaAddress);
        sponsorVault = ISponsorVault(sponsorVaultAddress);
        treasury = ITreasuryDeposit(treasuryAddress);
        grantRegistry = IGrantRegistry(grantRegistryAddress);
        cyberRegistry = ICyberRegistry(cyberRegistryAddress);
        council = councilAddress;
        minSliceBps = minSliceBps_;
        upfrontBps = upfrontBps_;
        fulfillWindow = fulfillWindow_;
    }

    function setBlacklisted(address fabricator, bool banned) external {
        if (msg.sender != council) revert NotCouncil();
        fabricatorBanned[fabricator] = banned;
        emit FabricatorBanned(fabricator, banned);
    }

    function createOffer(
        uint256 kitId,
        uint64 version,
        bytes32 designHash,
        string calldata contentUri,
        uint256 price,
        uint16 sliceBps,
        uint256 quantity,
        bytes32 pubkey
    ) external returns (uint256 offerId) {
        if (fabricatorBanned[msg.sender]) revert Banned();
        if (sliceBps < minSliceBps || sliceBps > BPS - upfrontBps) revert BadSlice();
        offerId = offerCount;
        offerCount = offerId + 1;
        offers[offerId] = Offer({
            fabricator: msg.sender,
            kitId: kitId,
            version: version,
            designHash: designHash,
            contentUri: contentUri,
            price: price,
            sliceBps: sliceBps,
            quantity: quantity,
            pubkey: pubkey,
            exists: true,
            openOrders: 0,
            grantId: 0,
            grantBps: 0,
            grantLinked: false,
            cyberSwagBps: 0
        });
        emit OfferCreated(offerId, msg.sender, kitId, version, designHash, contentUri, price, sliceBps, quantity);
    }

    function updateOffer(uint256 offerId, uint256 price, uint16 sliceBps, uint256 quantity) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (sliceBps < minSliceBps || sliceBps > BPS - upfrontBps) revert BadSlice();
        o.price = price;
        o.sliceBps = sliceBps;
        o.quantity = quantity;
        emit OfferUpdated(offerId, price, sliceBps, quantity);
    }

    function linkGrant(uint256 offerId, uint256 grantId) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (grantRegistry.totalSharesOf(grantId) == 0) revert NoFunders();
        o.grantId = grantId;
        o.grantBps = grantRegistry.salesShareBps(grantId);
        o.grantLinked = true;
        emit GrantLinked(offerId, grantId, o.grantBps);
    }

    function setCyberSwagBps(uint256 offerId, uint16 cyberSwagBps) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (cyberSwagBps > BPS - upfrontBps) revert BadSlice();
        o.cyberSwagBps = cyberSwagBps;
        emit CyberSwagSet(offerId, cyberSwagBps);
    }

    function deleteOffer(uint256 offerId) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (o.openOrders != 0) revert HasOpenOrders();
        delete offers[offerId];
        emit OfferDeleted(offerId);
    }

    function buy(uint256 offerId, bytes32 shippingCommitment, address oracle) external returns (uint256 orderId) {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (fabricatorBanned[o.fabricator]) revert Banned();
        if (o.quantity == 0) revert SoldOut();

        uint256 price = o.price;
        if (!mona.transferFrom(msg.sender, address(this), price)) revert TransferFailed();

        uint256 upfront = price * upfrontBps / BPS;
        uint256 escrowAmount = price - upfront;
        uint256 slice = price * o.sliceBps / BPS;
        uint256 grantSlice = o.grantLinked ? price * o.grantBps / BPS : 0;
        uint256 cyberSlice = price * o.cyberSwagBps / BPS;
        if (slice + grantSlice + cyberSlice > escrowAmount) revert SharesExceedEscrow();
        address fabricator = o.fabricator;

        o.quantity -= 1;
        o.openOrders += 1;

        orderId = orderCount;
        orderCount = orderId + 1;
        orders[orderId] = Order({
            offerId: offerId,
            buyer: msg.sender,
            oracle: oracle,
            escrowAmount: escrowAmount,
            slice: slice,
            grantId: o.grantLinked ? o.grantId : 0,
            grantSlice: grantSlice,
            cyberSlice: cyberSlice,
            shippingCommitment: shippingCommitment,
            deadline: uint64(block.timestamp) + fulfillWindow,
            open: true
        });

        if (upfront > 0 && !mona.transfer(fabricator, upfront)) revert TransferFailed();
        emit OrderPlaced(orderId, offerId, msg.sender, oracle, shippingCommitment);
    }

    function confirmReceipt(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (ord.buyer != msg.sender) revert NotBuyer();
        _release(orderId, ord, false);
    }

    function confirmDelivery(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (ord.oracle == address(0) || ord.oracle != msg.sender) revert NotOracle();
        _release(orderId, ord, true);
    }

    function cancelByFabricator(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (offers[ord.offerId].fabricator != msg.sender) revert NotFabricator();
        _refund(orderId, ord);
    }

    function refundAfterTimeout(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (ord.buyer != msg.sender) revert NotBuyer();
        if (block.timestamp <= ord.deadline) revert TooEarly();
        _refund(orderId, ord);
    }

    function _release(uint256 orderId, Order storage ord, bool byOracle) internal {
        Offer storage o = offers[ord.offerId];
        address fabricator = o.fabricator;
        uint256 kitId = o.kitId;
        uint256 escrowAmount = ord.escrowAmount;
        uint256 sl = ord.slice;
        uint256 gSlice = ord.grantSlice;
        uint256 gId = ord.grantId;
        uint256 cSlice = ord.cyberSlice;
        _markClosed(ord);

        _routeSlice(sl);
        uint256 toFab = escrowAmount - sl;
        if (gSlice > 0) {
            mona.approve(address(grantRegistry), gSlice);
            grantRegistry.notifyReward(gId, gSlice);
            toFab -= gSlice;
        }
        if (cSlice > 0 && cyberRegistry.totalWeight(kitId) > 0) {
            mona.approve(address(cyberRegistry), cSlice);
            cyberRegistry.notifyReward(kitId, cSlice);
            toFab -= cSlice;
        }
        if (toFab > 0 && !mona.transfer(fabricator, toFab)) revert TransferFailed();
        emit OrderReleased(orderId, byOracle);
    }

    function _refund(uint256 orderId, Order storage ord) internal {
        address buyer = ord.buyer;
        uint256 amount = ord.escrowAmount;
        _markClosed(ord);
        if (amount > 0 && !mona.transfer(buyer, amount)) revert TransferFailed();
        emit OrderRefunded(orderId);
    }

    function _markClosed(Order storage ord) internal {
        ord.open = false;
        offers[ord.offerId].openOrders -= 1;
        ord.escrowAmount = 0;
        ord.slice = 0;
        ord.grantSlice = 0;
        ord.cyberSlice = 0;
    }

    function _routeSlice(uint256 slice) internal {
        if (slice == 0) return;
        if (sponsorVault.totalPoints() > 0) {
            mona.approve(address(sponsorVault), slice);
            sponsorVault.notifyReward(slice);
        } else {
            mona.approve(address(treasury), slice);
            treasury.deposit(slice);
        }
    }
}
