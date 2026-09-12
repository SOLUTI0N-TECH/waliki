// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Waliki payment gateway (Phase 1, Buildathon MVP).
///
/// Non-custodial by construction: pay() moves tUSDT straight from the payer to
/// the merchant's payout address; this contract never holds funds.
/// The cash register verifies each sale by listening to PaymentReceived.
///
/// One router serves every shop: a merchant is a row in here, not a separate
/// deployment. Each owner authorizes their own cashiers, and every sale is
/// attributed to the cashier that issued it -- without that cashier ever
/// signing a transaction or holding gas. See cashierOf().
contract WalikiRouter {
    using SafeERC20 for IERC20;

    struct Merchant {
        address owner; // the only address allowed to manage the shop (the lock)
        address payout; // address that receives the payments
        string name;
    }

    IERC20 public immutable token;
    uint256 public merchantCount;
    mapping(uint256 => Merchant) public merchants;

    /// merchantId => saleId => amount paid (0 = unpaid). Prevents paying the
    /// same sale twice and lets the payment page detect "already paid".
    mapping(uint256 => mapping(bytes32 => uint256)) public paidAmount;

    /// merchantId => address => allowed to issue sales for this shop. The
    /// owner is registered in here as well, so pay() only ever consults this
    /// one mapping and handing the shop over does not void the sales the
    /// previous owner still has on a screen.
    mapping(uint256 => mapping(address => bool)) public isCashier;

    /// merchantId => address that has been offered the shop and has not
    /// accepted it yet. Handing a shop over is the only irreversible action
    /// in here, so it takes two steps: a typo into a valid-but-wrong address
    /// would otherwise lock the owner out forever.
    mapping(uint256 => address) public pendingOwner;

    event MerchantRegistered(
        uint256 indexed merchantId,
        address indexed owner,
        address payout,
        string name
    );
    event PayoutAddressChanged(uint256 indexed merchantId, address newPayout);
    event PaymentReceived(
        uint256 indexed merchantId,
        bytes32 indexed saleId,
        address indexed payer,
        uint256 amount,
        address payout
    );
    /// Emitted again, with a new label, when an already active cashier is
    /// re-added: that is how a register gets renamed.
    event CashierAdded(uint256 indexed merchantId, address indexed cashier, string label);
    event CashierRemoved(uint256 indexed merchantId, address indexed cashier);
    event OwnershipTransferStarted(
        uint256 indexed merchantId,
        address indexed from,
        address indexed to
    );
    event MerchantOwnershipTransferred(
        uint256 indexed merchantId,
        address indexed from,
        address indexed to
    );

    modifier onlyMerchantOwner(uint256 merchantId) {
        require(merchants[merchantId].owner == msg.sender, "Waliki: solo el dueno del comercio");
        _;
    }

    constructor(IERC20 _token) {
        token = _token;
    }

    /// The cashier a sale belongs to, carried in the first 20 bytes of its id
    /// (the remaining 12 are random). Keeping the attribution inside the sale
    /// id -- which is an indexed field of PaymentReceived -- means the payer
    /// cannot forge it: pointing a payment at another cashier would require
    /// changing the sale id, and then it is simply a different sale, one that
    /// no cash register is waiting for.
    function cashierOf(bytes32 saleId) public pure returns (address) {
        return address(bytes20(saleId));
    }

    function registerMerchant(
        address payout,
        string calldata name
    ) external returns (uint256 merchantId) {
        require(payout != address(0), "Waliki: direccion de cobro invalida");
        merchantId = ++merchantCount;
        merchants[merchantId] = Merchant({owner: msg.sender, payout: payout, name: name});
        isCashier[merchantId][msg.sender] = true;
        emit MerchantRegistered(merchantId, msg.sender, payout, name);
        emit CashierAdded(merchantId, msg.sender, "");
    }

    function setPayoutAddress(
        uint256 merchantId,
        address newPayout
    ) external onlyMerchantOwner(merchantId) {
        require(newPayout != address(0), "Waliki: direccion de cobro invalida");
        merchants[merchantId].payout = newPayout;
        emit PayoutAddressChanged(merchantId, newPayout);
    }

    /// Authorizes an address to issue sales for this shop. The cashier never
    /// signs anything: the owner registers the identity their app generated,
    /// and the label is only there to give the register a name on screen.
    function addCashier(
        uint256 merchantId,
        address cashier,
        string calldata label
    ) external onlyMerchantOwner(merchantId) {
        require(cashier != address(0), "Waliki: cajero invalido");
        isCashier[merchantId][cashier] = true;
        emit CashierAdded(merchantId, cashier, label);
    }

    /// Takes the authorization away. Sales this cashier issued and nobody has
    /// paid yet stop being payable immediately -- that is the point.
    function removeCashier(
        uint256 merchantId,
        address cashier
    ) external onlyMerchantOwner(merchantId) {
        require(isCashier[merchantId][cashier], "Waliki: no es cajero");
        require(cashier != merchants[merchantId].owner, "Waliki: el dueno no se puede quitar");
        isCashier[merchantId][cashier] = false;
        emit CashierRemoved(merchantId, cashier);
    }

    /// Step 1 of handing the shop over. Nothing changes until the new owner
    /// calls acceptMerchantOwnership(), which proves they hold the key.
    function transferMerchantOwnership(
        uint256 merchantId,
        address newOwner
    ) external onlyMerchantOwner(merchantId) {
        require(newOwner != address(0), "Waliki: dueno invalido");
        require(newOwner != msg.sender, "Waliki: ya eres el dueno");
        pendingOwner[merchantId] = newOwner;
        emit OwnershipTransferStarted(merchantId, msg.sender, newOwner);
    }

    function cancelMerchantOwnershipTransfer(
        uint256 merchantId
    ) external onlyMerchantOwner(merchantId) {
        require(pendingOwner[merchantId] != address(0), "Waliki: no hay traspaso pendiente");
        delete pendingOwner[merchantId];
        emit OwnershipTransferStarted(merchantId, msg.sender, address(0));
    }

    /// Step 2. The previous owner stays on as a cashier: the sales they have
    /// on a screen right now remain payable, and the new owner can remove
    /// them afterwards.
    function acceptMerchantOwnership(uint256 merchantId) external {
        require(pendingOwner[merchantId] == msg.sender, "Waliki: no eres el dueno propuesto");
        address previousOwner = merchants[merchantId].owner;
        delete pendingOwner[merchantId];
        merchants[merchantId].owner = msg.sender;
        if (!isCashier[merchantId][msg.sender]) {
            isCashier[merchantId][msg.sender] = true;
            emit CashierAdded(merchantId, msg.sender, "");
        }
        emit MerchantOwnershipTransferred(merchantId, previousOwner, msg.sender);
    }

    function pay(uint256 merchantId, bytes32 saleId, uint256 amount) external {
        Merchant storage m = merchants[merchantId];
        require(m.owner != address(0), "Waliki: comercio inexistente");
        require(amount > 0, "Waliki: monto cero");
        require(paidAmount[merchantId][saleId] == 0, "Waliki: venta ya pagada");
        require(isCashier[merchantId][cashierOf(saleId)], "Waliki: cajero no autorizado");
        paidAmount[merchantId][saleId] = amount;
        token.safeTransferFrom(msg.sender, m.payout, amount);
        emit PaymentReceived(merchantId, saleId, msg.sender, amount, m.payout);
    }
}
