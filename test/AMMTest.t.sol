// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AMM.sol";
import "../src/ERC20Token.sol";
import "../src/LPToken.sol";

/**
 * @title AMMTest
 * @notice Comprehensive test suite for the constant-product AMM.
 *         Covers all required scenarios from the assignment spec.
 */
contract AMMTest is Test {
    AMM        internal amm;
    ERC20Token internal tokenA;
    ERC20Token internal tokenB;
    LPToken    internal lp;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");

    // Initial liquidity: 1 000 000 tokenA : 500 000 tokenB (price = 0.5 B/A)
    uint256 internal constant INIT_A = 1_000_000e18;
    uint256 internal constant INIT_B =   500_000e18;

    // ── Setup ─────────────────────────────────────────────────────────────────

    function setUp() public {
        tokenA = new ERC20Token("Token A", "TKA", 18);
        tokenB = new ERC20Token("Token B", "TKB", 18);
        amm    = new AMM(address(tokenA), address(tokenB));
        lp     = amm.lpToken();

        // Mint tokens to actors
        tokenA.mint(alice, INIT_A * 10);
        tokenB.mint(alice, INIT_B * 10);
        tokenA.mint(bob,   INIT_A * 2);
        tokenB.mint(bob,   INIT_B * 2);
        tokenA.mint(carol, INIT_A);
        tokenB.mint(carol, INIT_B);

        // Alice adds initial liquidity
        vm.startPrank(alice);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        amm.addLiquidity(INIT_A, INIT_B, 0, 0);
        vm.stopPrank();
    }

    // ────────────────── 1. LIQUIDITY TESTS ───────────────────────────────────

    /// Test 1: First provider sets reserves correctly
    function test_addLiquidity_firstProvider() public view {
        assertEq(amm.reserveA(), INIT_A);
        assertEq(amm.reserveB(), INIT_B);
        assertGt(lp.totalSupply(), 0);
    }

    /// Test 2: Subsequent provider receives proportional LP tokens
    function test_addLiquidity_subsequentProvider() public {
        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);

        uint256 lpBefore   = lp.totalSupply();
        uint256 reserveABefore = amm.reserveA();
        uint256 reserveBBefore = amm.reserveB();

        // Bob adds 10 % of pool
        uint256 addA = INIT_A / 10;
        uint256 addB = INIT_B / 10;
        (,, uint256 lpMinted) = amm.addLiquidity(addA, addB, 0, 0);

        assertEq(amm.reserveA(), reserveABefore + addA);
        assertEq(amm.reserveB(), reserveBBefore + addB);
        assertApproxEqRel(lpMinted, lpBefore / 10, 0.01e18); // ~10 % of existing LP
        vm.stopPrank();
    }

    /// Test 3: Remove full liquidity
    function test_removeLiquidity_full() public {
        uint256 aliceLP = lp.balanceOf(alice);
        assertGt(aliceLP, 0);

        vm.startPrank(alice);
        lp.approve(address(amm), type(uint256).max);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(aliceLP, 0, 0);
        vm.stopPrank();

        assertGt(outA, 0);
        assertGt(outB, 0);
    }

    /// Test 4: Remove partial liquidity
    function test_removeLiquidity_partial() public {
        uint256 aliceLP   = lp.balanceOf(alice);
        uint256 halfLP    = aliceLP / 2;

        vm.startPrank(alice);
        lp.approve(address(amm), type(uint256).max);
        (uint256 outA, uint256 outB) = amm.removeLiquidity(halfLP, 0, 0);
        vm.stopPrank();

        // Should receive ~half of reserves
        assertApproxEqRel(outA, INIT_A / 2, 0.02e18);
        assertApproxEqRel(outB, INIT_B / 2, 0.02e18);
    }

    /// Test 5: Remove liquidity with slippage protection
    function test_removeLiquidity_slippageReverts() public {
        uint256 aliceLP = lp.balanceOf(alice);
        vm.startPrank(alice);
        lp.approve(address(amm), type(uint256).max);

        vm.expectRevert();
        amm.removeLiquidity(aliceLP, type(uint256).max, type(uint256).max);
        vm.stopPrank();
    }

    // ────────────────── 2. SWAP TESTS ─────────────────────────────────────────

    /// Test 6: Swap tokenA → tokenB produces expected output
    function test_swap_AtoB() public {
        uint256 amountIn = 10_000e18; // 1 % of pool
        uint256 expected = amm.getAmountOut(amountIn, amm.reserveA(), amm.reserveB());

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        uint256 before  = tokenB.balanceOf(bob);
        uint256 amountOut = amm.swap(address(tokenA), amountIn, 0);
        vm.stopPrank();

        assertEq(amountOut, expected);
        assertEq(tokenB.balanceOf(bob), before + amountOut);
    }

    /// Test 7: Swap tokenB → tokenA works in reverse direction
    function test_swap_BtoA() public {
        uint256 amountIn = 5_000e18;
        uint256 expected = amm.getAmountOut(amountIn, amm.reserveB(), amm.reserveA());

        vm.startPrank(bob);
        tokenB.approve(address(amm), type(uint256).max);
        uint256 before  = tokenA.balanceOf(bob);
        uint256 amountOut = amm.swap(address(tokenB), amountIn, 0);
        vm.stopPrank();

        assertEq(amountOut, expected);
        assertEq(tokenA.balanceOf(bob), before + amountOut);
    }

    /// Test 8: k must NOT decrease after a swap (fees make it increase)
    function test_swap_kNeverDecreases() public {
        uint256 kBefore = amm.getK();

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        amm.swap(address(tokenA), 50_000e18, 0);
        vm.stopPrank();

        assertGe(amm.getK(), kBefore, "k should not decrease after swap");
    }

    /// Test 9: Slippage protection — swap reverts when output below minimum
    function test_swap_slippage_reverts() public {
        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        vm.expectRevert();
        amm.swap(address(tokenA), 1_000e18, type(uint256).max);
        vm.stopPrank();
    }

    /// Test 10: Swap with invalid token address reverts
    function test_swap_invalidToken_reverts() public {
        vm.startPrank(bob);
        vm.expectRevert(AMM.InvalidToken.selector);
        amm.swap(address(0xdead), 1_000e18, 0);
        vm.stopPrank();
    }

    /// Test 11: Swap with zero amount reverts
    function test_swap_zeroAmount_reverts() public {
        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.swap(address(tokenA), 0, 0);
        vm.stopPrank();
    }

/// Test 12: Large swap causes high price impact (output < proportional)
    function test_swap_largePriceImpact() public view { // ДОБАВЛЕНО view
        // Swap 50 % of reserveA — should get much less than 50 % of reserveB due to impact
        uint256 bigSwap  = amm.reserveA() / 2;
        uint256 naiveOut = amm.reserveB() / 2;
        uint256 realOut  = amm.getAmountOut(bigSwap, amm.reserveA(), amm.reserveB());

        // Real output is significantly less than naive proportional
        assertLt(realOut, (naiveOut * 90) / 100);
    }

    /// Test 13: k is consistent after multiple swaps
    function test_swap_kGrowsMonotonically() public {
        uint256 k0 = amm.getK();

        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);

        amm.swap(address(tokenA), 1_000e18, 0);
        uint256 k1 = amm.getK();
        amm.swap(address(tokenB), 500e18, 0);
        uint256 k2 = amm.getK();
        vm.stopPrank();

        assertGe(k1, k0);
        assertGe(k2, k1);
    }

    /// Test 14: addLiquidity with zero amounts reverts
    function test_addLiquidity_zeroAmount_reverts() public {
        vm.startPrank(bob);
        tokenA.approve(address(amm), type(uint256).max);
        tokenB.approve(address(amm), type(uint256).max);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.addLiquidity(0, 0, 0, 0);
        vm.stopPrank();
    }

    /// Test 15: removeLiquidity with zero LP reverts
    function test_removeLiquidity_zeroLP_reverts() public {
        vm.startPrank(alice);
        lp.approve(address(amm), type(uint256).max);
        vm.expectRevert(AMM.ZeroAmount.selector);
        amm.removeLiquidity(0, 0, 0);
        vm.stopPrank();
    }

    /// Test 16: getAmountOut formula correctness (manual calculation)
    function test_getAmountOut_formula() public view {
        // amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
        uint256 amountIn  = 1_000e18;
        uint256 rIn       = 1_000_000e18;
        uint256 rOut      = 500_000e18;
        uint256 expected  = (amountIn * 997 * rOut) / (rIn * 1000 + amountIn * 997);
        assertEq(amm.getAmountOut(amountIn, rIn, rOut), expected);
    }

    // ────────────────── 3. FUZZ TEST ──────────────────────────────────────────

    /**
     * @notice Fuzz test: any valid swap keeps k non-decreasing and output > 0.
     */
    function testFuzz_swap_kPreservation(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e15, amm.reserveA() / 3); // avoid draining pool

        uint256 kBefore = amm.getK();

        vm.startPrank(carol);
        tokenA.approve(address(amm), type(uint256).max);
        uint256 out = amm.swap(address(tokenA), amountIn, 0);
        vm.stopPrank();

        assertGt(out, 0, "output must be positive");
        assertGe(amm.getK(), kBefore, "k must not decrease");
    }
}
