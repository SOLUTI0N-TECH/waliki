// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Test tUSDT for the Waliki demo on Base Sepolia.
/// 6 decimals (like real USDT) and a public faucet with cooldown, so any
/// demo wallet can get balance without depending on third parties.
contract TestUSDT is ERC20 {
    uint256 public constant FAUCET_AMOUNT = 100 * 10 ** 6; // 100 tUSDT
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    mapping(address => uint256) public lastFaucetAt;

    constructor() ERC20("Test USDT (Waliki demo)", "tUSDT") {
        // Initial deployer supply to prefund the demo-kit wallets.
        _mint(msg.sender, 10_000 * 10 ** 6);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function faucet() external {
        require(
            block.timestamp >= lastFaucetAt[msg.sender] + FAUCET_COOLDOWN,
            "tUSDT: faucet en cooldown"
        );
        lastFaucetAt[msg.sender] = block.timestamp;
        _mint(msg.sender, FAUCET_AMOUNT);
    }
}
