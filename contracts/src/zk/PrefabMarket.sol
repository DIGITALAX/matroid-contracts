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
    function kitOf(uint256 grantId) external view returns (uint256);
    function totalSharesOf(uint256 grantId) external view returns (uint256);
    function notifyReward(uint256 grantId, uint256 amount) external;
}

interface ICyberRegistry {
    function ownerOf(uint256 agentId) external view returns (address);
    function inSchema(uint256 agentId, uint256 kitId) external view returns (bool);
}

interface IBlacklist {
    function isBanned(address who) external view returns (bool);
}

interface IDxRouter {
    function routeIn(address user, uint256 amount, address to) external;
}

contract PrefabMarket {
    uint16 public constant BPS = 10000;
    uint256 public constant MAX_AGENTS = 10;
    uint64 public constant MIN_CONFIRM_WINDOW = 1 days;
    // of the protocol slice: 40% to gas sponsors (when any), the rest always to the treasury
    uint16 public constant SPONSOR_SPLIT_BPS = 4000;

    IERC20 public immutable mona;
    ISponsorVault public immutable sponsorVault;
    ITreasuryDeposit public immutable treasury;
    IGrantRegistry public immutable grantRegistry;
    ICyberRegistry public immutable cyberRegistry;
    uint16 public immutable minSliceBps;
    uint16 public immutable upfrontBps;
    IBlacklist public immutable blacklist;
    // when set, buyer payments are pulled through the registered dx.app
    // project (DxProject) so every sale is recorded as matroid activity;
    // when zero, payments come straight from the buyer (standalone mode)
    IDxRouter public immutable dxRouter;

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
        uint64 confirmWindow;
    }

    struct Order {
        uint256 offerId;
        address buyer;
        address oracle;
        uint256 quantity;
        uint256 escrowAmount;
        uint256 slice;
        uint256 grantId;
        uint256 grantSlice;
        uint256 cyberSlice;
        bytes32 shippingCommitment;
        uint64 deadline;
        bool open;
        uint8 stage;
    }

    mapping(uint256 => Offer) public offers;
    uint256 public offerCount;
    mapping(uint256 => Order) public orders;
    uint256 public orderCount;
    mapping(uint256 => uint256[]) internal offerAgentIds;
    mapping(uint256 => mapping(uint256 => bool)) public agentLinked;

    event OfferCreated(uint256 indexed offerId, address indexed fabricator, uint256 kitId, uint64 version, bytes32 designHash, string contentUri, uint256 price, uint16 sliceBps, uint256 quantity, uint64 confirmWindow);
    event OfferUpdated(uint256 indexed offerId, uint256 price, uint16 sliceBps, uint256 quantity, string contentUri, uint64 confirmWindow);
    event OfferDeleted(uint256 indexed offerId);
    event GrantLinked(uint256 indexed offerId, uint256 indexed grantId, uint16 grantBps);
    event GrantUnlinked(uint256 indexed offerId);
    event AgentLinked(uint256 indexed offerId, uint256 indexed agentId);
    event AgentUnlinked(uint256 indexed offerId, uint256 indexed agentId);
    event PubkeySet(uint256 indexed offerId, bytes32 pubkey);
    event CyberSwagSet(uint256 indexed offerId, uint16 cyberSwagBps);
    event OrderPlaced(uint256 indexed orderId, uint256 indexed offerId, address indexed buyer, uint256 quantity, address oracle, bytes32 shippingCommitment, bytes encryptedShipping);
    event OrderSlices(uint256 indexed orderId, uint256 total, uint256 slice, uint256 grantSlice, uint256 cyberSlice, uint256 grantId);
    event OrderReleased(uint256 indexed orderId, bool byOracle);
    event OrderRefunded(uint256 indexed orderId);
    event OrderStageSet(uint256 indexed orderId, uint8 stage, uint64 deadline);

    error NotFabricator();
    error NoOffer();
    error BadSlice();
    error SoldOut();
    error InvalidQuantity();
    error InvalidStage();
    error HasOpenOrders();
    error OrderClosed();
    error NotBuyer();
    error NotOracle();
    error AlreadyShipped();
    error Banned();
    error NoFunders();
    error SharesExceedEscrow();
    error TransferFailed();
    error TooEarly();
    error BadWindow();
    error NoAgent();
    error KitMismatch();
    error AlreadyLinked();
    error NotLinked();
    error TooManyAgents();

    constructor(
        address monaAddress,
        address sponsorVaultAddress,
        address treasuryAddress,
        address grantRegistryAddress,
        address cyberRegistryAddress,
        uint16 minSliceBps_,
        uint16 upfrontBps_,
        address blacklistAddress,
        address dxRouterAddress
    ) {
        mona = IERC20(monaAddress);
        sponsorVault = ISponsorVault(sponsorVaultAddress);
        treasury = ITreasuryDeposit(treasuryAddress);
        grantRegistry = IGrantRegistry(grantRegistryAddress);
        cyberRegistry = ICyberRegistry(cyberRegistryAddress);
        minSliceBps = minSliceBps_;
        upfrontBps = upfrontBps_;
        blacklist = IBlacklist(blacklistAddress);
        dxRouter = IDxRouter(dxRouterAddress);
    }

    function createOffer(
        uint256 kitId,
        uint64 version,
        bytes32 designHash,
        string calldata contentUri,
        uint256 price,
        uint16 sliceBps,
        uint256 quantity,
        bytes32 pubkey,
        uint64 confirmWindow,
        uint16 cyberSwagBps
    ) external returns (uint256 offerId) {
        if (blacklist.isBanned(msg.sender)) revert Banned();
        if (sliceBps < minSliceBps || sliceBps > BPS - upfrontBps) revert BadSlice();
        if (cyberSwagBps > BPS - upfrontBps) revert BadSlice();
        if (confirmWindow < MIN_CONFIRM_WINDOW) revert BadWindow();
        offerId = offerCount + 1;
        offerCount = offerId;
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
            cyberSwagBps: cyberSwagBps,
            confirmWindow: confirmWindow
        });
        emit OfferCreated(offerId, msg.sender, kitId, version, designHash, contentUri, price, sliceBps, quantity, confirmWindow);
        if (cyberSwagBps > 0) {
            emit CyberSwagSet(offerId, cyberSwagBps);
        }
    }

    function updateOffer(
        uint256 offerId,
        uint256 price,
        uint16 sliceBps,
        uint256 quantity,
        string calldata newContentUri,
        uint64 confirmWindow,
        uint16 cyberSwagBps
    ) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (sliceBps < minSliceBps || sliceBps > BPS - upfrontBps) revert BadSlice();
        if (cyberSwagBps > BPS - upfrontBps) revert BadSlice();
        if (confirmWindow < MIN_CONFIRM_WINDOW) revert BadWindow();
        o.price = price;
        o.sliceBps = sliceBps;
        o.quantity = quantity;
        o.contentUri = newContentUri;
        o.confirmWindow = confirmWindow;
        emit OfferUpdated(offerId, price, sliceBps, quantity, newContentUri, confirmWindow);
        if (o.cyberSwagBps != cyberSwagBps) {
            o.cyberSwagBps = cyberSwagBps;
            emit CyberSwagSet(offerId, cyberSwagBps);
        }
    }

    function setPubkey(uint256 offerId, bytes32 pubkey) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        o.pubkey = pubkey;
        emit PubkeySet(offerId, pubkey);
    }

    function linkGrant(uint256 offerId, uint256 grantId, uint16 grantBps) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (grantRegistry.totalSharesOf(grantId) == 0) revert NoFunders();
        if (grantRegistry.kitOf(grantId) != o.kitId) revert KitMismatch();
        if (grantBps == 0 || grantBps > BPS - upfrontBps) revert BadSlice();
        o.grantId = grantId;
        o.grantBps = grantBps;
        o.grantLinked = true;
        emit GrantLinked(offerId, grantId, grantBps);
    }

    function unlinkGrant(uint256 offerId) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (!o.grantLinked) revert NotLinked();
        o.grantId = 0;
        o.grantBps = 0;
        o.grantLinked = false;
        emit GrantUnlinked(offerId);
    }

    function linkAgent(uint256 offerId, uint256 agentId) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (cyberRegistry.ownerOf(agentId) == address(0)) revert NoAgent();
        if (!cyberRegistry.inSchema(agentId, o.kitId)) revert KitMismatch();
        if (agentLinked[offerId][agentId]) revert AlreadyLinked();
        if (offerAgentIds[offerId].length >= MAX_AGENTS) revert TooManyAgents();
        agentLinked[offerId][agentId] = true;
        offerAgentIds[offerId].push(agentId);
        emit AgentLinked(offerId, agentId);
    }

    function unlinkAgent(uint256 offerId, uint256 agentId) external {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (o.fabricator != msg.sender) revert NotFabricator();
        if (!agentLinked[offerId][agentId]) revert NotLinked();
        agentLinked[offerId][agentId] = false;
        uint256[] storage ids = offerAgentIds[offerId];
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == agentId) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                break;
            }
        }
        emit AgentUnlinked(offerId, agentId);
    }

    function agentsOf(uint256 offerId) external view returns (uint256[] memory) {
        return offerAgentIds[offerId];
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

    function buy(
        uint256 offerId,
        uint256 quantity,
        bytes32 shippingCommitment,
        address oracle,
        bytes calldata encryptedShipping
    ) external returns (uint256 orderId) {
        Offer storage o = offers[offerId];
        if (!o.exists) revert NoOffer();
        if (blacklist.isBanned(msg.sender)) revert Banned();
        if (blacklist.isBanned(o.fabricator)) revert Banned();
        if (o.quantity == 0) revert SoldOut();
        if (quantity == 0 || quantity > o.quantity) revert InvalidQuantity();

        uint256 total = o.price * quantity;
        if (address(dxRouter) != address(0)) {
            dxRouter.routeIn(msg.sender, total, address(this));
        } else {
            if (!mona.transferFrom(msg.sender, address(this), total)) revert TransferFailed();
        }

        uint256 upfront = total * upfrontBps / BPS;
        uint256 escrowAmount = total - upfront;
        uint256 slice = total * o.sliceBps / BPS;
        uint256 grantSlice = o.grantLinked ? total * o.grantBps / BPS : 0;
        uint256 cyberSlice = total * o.cyberSwagBps / BPS;
        if (slice + grantSlice + cyberSlice > escrowAmount) revert SharesExceedEscrow();
        address fabricator = o.fabricator;

        o.quantity -= quantity;
        o.openOrders += 1;

        orderId = orderCount + 1;
        orderCount = orderId;
        orders[orderId] = Order({
            offerId: offerId,
            buyer: msg.sender,
            oracle: oracle,
            quantity: quantity,
            escrowAmount: escrowAmount,
            slice: slice,
            grantId: o.grantLinked ? o.grantId : 0,
            grantSlice: grantSlice,
            cyberSlice: cyberSlice,
            shippingCommitment: shippingCommitment,
            deadline: 0,
            open: true,
            stage: 0
        });

        if (upfront > 0 && !mona.transfer(fabricator, upfront)) revert TransferFailed();
        emit OrderPlaced(orderId, offerId, msg.sender, quantity, oracle, shippingCommitment, encryptedShipping);
    }

    function setOrderStage(uint256 orderId, uint8 stage) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (offers[ord.offerId].fabricator != msg.sender) revert NotFabricator();
        if (stage <= ord.stage || stage > 2) revert InvalidStage();
        ord.stage = stage;
        if (stage == 2) {
            ord.deadline = uint64(block.timestamp) + offers[ord.offerId].confirmWindow;
        }
        emit OrderStageSet(orderId, stage, ord.deadline);
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

    function cancelByBuyer(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (ord.buyer != msg.sender) revert NotBuyer();
        if (ord.stage >= 2) revert AlreadyShipped();
        _refund(orderId, ord);
    }

    function claimAfterDeadline(uint256 orderId) external {
        Order storage ord = orders[orderId];
        if (!ord.open) revert OrderClosed();
        if (offers[ord.offerId].fabricator != msg.sender) revert NotFabricator();
        if (ord.stage < 2 || ord.deadline == 0 || block.timestamp <= ord.deadline) revert TooEarly();
        _release(orderId, ord, false);
    }

    function _release(uint256 orderId, Order storage ord, bool byOracle) internal {
        Offer storage o = offers[ord.offerId];
        address fabricator = o.fabricator;
        uint256 offerId = ord.offerId;
        uint256 escrowAmount = ord.escrowAmount;
        uint256 sl = ord.slice;
        uint256 gSlice = ord.grantSlice;
        uint256 gId = ord.grantId;
        uint256 cSlice = ord.cyberSlice;
        _markClosed(ord);

        _routeSlice(sl);
        uint256 toFab = escrowAmount - sl;
        uint256 gPaid = 0;
        if (gSlice > 0 && o.grantLinked && o.grantId == gId) {
            mona.approve(address(grantRegistry), gSlice);
            try grantRegistry.notifyReward(gId, gSlice) {
                gPaid = gSlice;
            } catch {
                mona.approve(address(grantRegistry), 0);
            }
        }
        toFab -= gPaid;
        uint256 cPaid = 0;
        if (cSlice > 0) {
            cPaid = _payAgents(offerId, o.kitId, cSlice);
            toFab -= cPaid;
        }
        if (toFab > 0 && !mona.transfer(fabricator, toFab)) revert TransferFailed();
        emit OrderSlices(orderId, escrowAmount, sl, gPaid, cPaid, gPaid > 0 ? gId : 0);
        emit OrderReleased(orderId, byOracle);
    }

    function _payAgents(uint256 offerId, uint256 kitId, uint256 cSlice) internal returns (uint256 paid) {
        uint256[] storage ids = offerAgentIds[offerId];
        uint256 n = ids.length;
        if (n == 0) return 0;
        address[] memory owners = new address[](n);
        uint256 count;
        for (uint256 i = 0; i < n; i++) {
            address agentOwner = cyberRegistry.ownerOf(ids[i]);
            if (agentOwner != address(0) && cyberRegistry.inSchema(ids[i], kitId)) {
                owners[count] = agentOwner;
                count++;
            }
        }
        if (count == 0) return 0;
        uint256 per = cSlice / count;
        if (per == 0) return 0;
        for (uint256 i = 0; i < count; i++) {
            if (!mona.transfer(owners[i], per)) revert TransferFailed();
        }
        return per * count;
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
        uint256 toSponsors = sponsorVault.totalPoints() > 0
            ? slice * SPONSOR_SPLIT_BPS / BPS
            : 0;
        uint256 toTreasury = slice - toSponsors;
        if (toSponsors > 0) {
            mona.approve(address(sponsorVault), toSponsors);
            sponsorVault.notifyReward(toSponsors);
        }
        if (toTreasury > 0) {
            mona.approve(address(treasury), toTreasury);
            treasury.deposit(toTreasury);
        }
    }
}
