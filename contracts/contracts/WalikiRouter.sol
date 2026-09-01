// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// Waliki payment gateway (Phase 1, Buildathon MVP).
///
/// Non-custodial by construction: pay() moves tUSDT straight from the payer to
/// the merchant's payout address; this contract never holds funds.
/// The cash register verifies each sale by listening to PaymentReceived.
contract WalikiRouter {
    using SafeERC20 for IERC20;

    struct Merchant {
        address owner; // the only address allowed to change the payout (the lock)
        address payout; // address that receives the payments
        string name;
    }

    IERC20 public immutable token;
    uint256 public merchantCount;
    mapping(uint256 => Merchant) public merchants;

    /// merchantId => saleId => amount paid (0 = unpaid). Prevents paying the
    /// same sale twice and lets the payment page detect "already paid".
    mapping(uint256 => mapping(bytes32 => uint256)) public paidAmount;

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

    constructor(IERC20 _token) {
        token = _token;
    }

    function registerMerchant(
        address payout,
        string calldata name
    ) external returns (uint256 merchantId) {
        require(payout != address(0), "Waliki: direccion de cobro invalida");
        merchantId = ++merchantCount;
        merchants[merchantId] = Merchant({owner: msg.sender, payout: payout, name: name});
        emit MerchantRegistered(merchantId, msg.sender, payout, name);
    }

    function setPayoutAddress(uint256 merchantId, address newPayout) external {
        Merchant storage m = merchants[merchantId];
        require(m.owner == msg.sender, "Waliki: solo el dueno del comercio");
        require(newPayout != address(0), "Waliki: direccion de cobro invalida");
        m.payout = newPayout;
        emit PayoutAddressChanged(merchantId, newPayout);
    }

    function pay(uint256 merchantId, bytes32 saleId, uint256 amount) external {
        Merchant storage m = merchants[merchantId];
        require(m.owner != address(0), "Waliki: comercio inexistente");
        require(amount > 0, "Waliki: monto cero");
        require(paidAmount[merchantId][saleId] == 0, "Waliki: venta ya pagada");
        paidAmount[merchantId][saleId] = amount;
        token.safeTransferFrom(msg.sender, m.payout, amount);
        emit PaymentReceived(merchantId, saleId, msg.sender, amount, m.payout);
    }
}
