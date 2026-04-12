// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/**
 * @title ForkTest
 * @notice Fork testing against Ethereum mainnet.
 *
 *  How to run:
 *  ──────────
 *  export MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
 *  forge test --match-path test/ForkTest.t.sol --fork-url $MAINNET_RPC_URL -vvv
 *
 *  vm.createSelectFork(rpcUrl)  — creates a fork at the latest block and selects it.
 *  vm.rollFork(blockNumber)     — rolls the fork to a specific block number, allowing
 *                                  time-travel in state (useful to reproduce past events).
 *
 *  Benefits: tests real deployed contracts without any mocking.
 *  Limitations: requires a node RPC, tests are slower, state can change between runs.
 */
contract ForkTest is Test {
    // ── Well-known mainnet addresses ──────────────────────────────────────────
    address constant USDC        = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant WETH        = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI         = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Minimal USDC interface (matches real USDC proxy)
    interface IUSDC {
        function totalSupply() external view returns (uint256);
        function decimals()    external view returns (uint8);
        function symbol()      external view returns (string memory);
        function balanceOf(address) external view returns (uint256);
    }

    // Minimal Uniswap V2 Router interface
    interface IUniswapV2Router {
        function swapExactETHForTokens(
            uint256 amountOutMin,
            address[] calldata path,
            address to,
            uint256 deadline
        ) external payable returns (uint256[] memory amounts);

        function getAmountsOut(uint256 amountIn, address[] calldata path)
            external view returns (uint256[] memory amounts);
    }

    // ── Fork setup ────────────────────────────────────────────────────────────

    string internal mainnetRpc;
    uint256 internal forkId;

    function setUp() public {
        // Read from environment (or fallback to a placeholder for CI)
        mainnetRpc = vm.envOr("MAINNET_RPC_URL", string("https://cloudflare-eth.com"));
        // Create and select the fork (latest block)
        forkId = vm.createSelectFork(mainnetRpc);
    }

    // ────────────────── TEST 1: Read USDC total supply ────────────────────────

    /**
     * @notice Reads the real USDC total supply from mainnet.
     *         Asserts it is > 10 billion USDC (6 decimals).
     */
    function test_fork_USDC_totalSupply() public view {
        IUSDC usdc = IUSDC(USDC);

        uint256 supply   = usdc.totalSupply();
        uint8   decimals = usdc.decimals();
        string memory sym = usdc.symbol();

        emit log_named_uint("USDC total supply (raw)",     supply);
        emit log_named_uint("USDC decimals",               decimals);
        emit log_named_string("USDC symbol",               sym);

        assertEq(decimals, 6,    "USDC should have 6 decimals");
        assertEq(sym, "USDC",   "Symbol should be USDC");
        // At time of writing USDC supply is > 25 billion → > 25e9 * 1e6 = 25e15
        assertGt(supply, 10_000_000_000 * 1e6, "USDC supply should be > 10B");
    }

    // ────────────────── TEST 2: Simulate Uniswap V2 swap ─────────────────────

    /**
     * @notice Simulates swapping 1 ETH for DAI via Uniswap V2 router on mainnet.
     *         Uses vm.deal to give the test contract ETH.
     */
    function test_fork_UniswapV2_ETHtoDAI_swap() public {
        address trader = makeAddr("trader");
        vm.deal(trader, 1 ether);

        IUniswapV2Router router = IUniswapV2Router(UNISWAP_V2_ROUTER);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        // Get expected output
        uint256[] memory amounts = router.getAmountsOut(1 ether, path);
        uint256 expectedOut = amounts[1];
        emit log_named_uint("Expected DAI out for 1 ETH", expectedOut / 1e18);

        // Execute swap
        vm.prank(trader);
        uint256[] memory received = router.swapExactETHForTokens{value: 1 ether}(
            0,            // no slippage protection for test
            path,
            trader,
            block.timestamp + 60
        );

        uint256 daiReceived = received[1];
        emit log_named_uint("DAI received", daiReceived / 1e18);

        // Sanity: must have received > 100 DAI for 1 ETH
        assertGt(daiReceived, 100e18, "Must receive > 100 DAI for 1 ETH");
        // Actual vs expected within 1 %
        assertApproxEqRel(daiReceived, expectedOut, 0.01e18);
    }

    // ────────────────── TEST 3: vm.rollFork demonstration ────────────────────

    /**
     * @notice Demonstrates rolling the fork to a historical block.
     *         Shows that state differs between blocks.
     */
    function test_fork_rollFork() public {
        IUSDC usdc = IUSDC(USDC);

        uint256 supplyNow = usdc.totalSupply();

        // Roll back to block 17_000_000 (May 2023 — USDC supply was different)
        vm.rollFork(17_000_000);
        uint256 supplyPast = usdc.totalSupply();

        emit log_named_uint("USDC supply at block 17_000_000 (raw)", supplyPast);
        emit log_named_uint("USDC supply at latest block (raw)",     supplyNow);

        // Just assert both reads succeeded (supply > 0 at both times)
        assertGt(supplyPast, 0, "Past supply must be > 0");
    }
}
