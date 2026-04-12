// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ERC20Token.sol";
import "../src/LPToken.sol";
import "../src/AMM.sol";
import "../src/LendingPool.sol";

/**
 * @title DeployAll
 * @notice Deploys the entire DeFi protocol suite:
 *           1. TokenA + TokenB (ERC-20 test tokens)
 *           2. AMM (constant-product market maker)
 *           3. LendingPool (overcollateralised lending)
 *
 *  Usage:
 *  ──────
 *  # Local Anvil
 *  forge script script/DeployAll.s.sol --broadcast --fork-url http://localhost:8545
 *
 *  # Sepolia testnet
 *  forge script script/DeployAll.s.sol --broadcast \
 *      --rpc-url $SEPOLIA_RPC_URL \
 *      --private-key $PRIVATE_KEY \
 *      --verify --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract DeployAll is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ── 1. Deploy ERC-20 tokens ──────────────────────────────────────────
        ERC20Token tokenA = new ERC20Token("Token Alpha", "TKA", 18);
        ERC20Token tokenB = new ERC20Token("Token Beta",  "TKB", 18);
        console2.log("TokenA deployed at:", address(tokenA));
        console2.log("TokenB deployed at:", address(tokenB));

        // Mint initial supply to deployer
        tokenA.mint(deployer, 10_000_000e18);
        tokenB.mint(deployer, 10_000_000e18);

        // ── 2. Deploy AMM ────────────────────────────────────────────────────
        AMM amm = new AMM(address(tokenA), address(tokenB));
        console2.log("AMM deployed at:   ", address(amm));
        console2.log("LP Token at:       ", address(amm.lpToken()));

        // Seed initial liquidity: 1 000 000 TKA : 1 000 000 TKB (1:1)
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(1_000_000e18, 1_000_000e18, 0, 0);
        console2.log("Initial liquidity added to AMM");

        // ── 3. Deploy LendingPool ────────────────────────────────────────────
        LendingPool pool = new LendingPool(address(tokenA));
        console2.log("LendingPool deployed at:", address(pool));

        // Seed pool with initial liquidity
        tokenA.approve(address(pool), type(uint256).max);
        pool.deposit(500_000e18);
        console2.log("LendingPool seeded with 500 000 TKA");

        vm.stopBroadcast();

        // ── Print summary ────────────────────────────────────────────────────
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("Network:     ", block.chainid);
        console2.log("Deployer:    ", deployer);
        console2.log("TokenA:      ", address(tokenA));
        console2.log("TokenB:      ", address(tokenB));
        console2.log("AMM:         ", address(amm));
        console2.log("LP Token:    ", address(amm.lpToken()));
        console2.log("LendingPool: ", address(pool));
    }
}
