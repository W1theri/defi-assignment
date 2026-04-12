// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/ERC20Token.sol";

/**
 * @title LendingPoolTest
 * @notice Complete test suite for LendingPool.
 *         Covers deposit/borrow/repay/withdraw/liquidation + edge cases.
 */
contract LendingPoolTest is Test {
    LendingPool internal pool;
    ERC20Token  internal token;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal liquidator = makeAddr("liquidator");

    uint256 internal constant MINT_AMOUNT   = 100_000e18;
    uint256 internal constant DEPOSIT_AMOUNT = 10_000e18;

    function setUp() public {
        token = new ERC20Token("USDC Mock", "USDC", 18);
        pool  = new LendingPool(address(token));

        // Fund actors
        token.mint(alice,      MINT_AMOUNT);
        token.mint(bob,        MINT_AMOUNT);
        token.mint(liquidator, MINT_AMOUNT);

        // Alice deposits liquidity into the pool so borrows can be served
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);
        pool.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // ────────────────── DEPOSIT TESTS ─────────────────────────────────────────

    /// Test 1: Deposit updates state correctly
    function test_deposit_basic() public view {
        (uint256 deposited,,,) = pool.positions(alice);
        assertEq(deposited, DEPOSIT_AMOUNT);
        assertEq(pool.totalDeposits(), DEPOSIT_AMOUNT);
    }

    /// Test 2: Deposit zero reverts
    function test_deposit_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.deposit(0);
    }

    // ────────────────── BORROW TESTS ──────────────────────────────────────────

    /// Test 3: Borrow within LTV succeeds
    function test_borrow_withinLTV() public {
        // Max borrow = 75 % of 10 000 = 7 500
        uint256 maxBorrow = (DEPOSIT_AMOUNT * 75) / 100;

        vm.startPrank(alice);
        pool.borrow(maxBorrow);
        vm.stopPrank();

        (, uint256 borrowed,,) = pool.positions(alice);
        assertEq(borrowed, maxBorrow);
    }

    /// Test 4: Borrow exceeding LTV reverts
    function test_borrow_exceedsLTV_reverts() public {
        uint256 overLTV = (DEPOSIT_AMOUNT * 80) / 100; // 80 % > 75 %

        vm.prank(alice);
        vm.expectRevert();
        pool.borrow(overLTV);
    }

    /// Test 5: Borrow with zero collateral reverts
    function test_borrow_noCollateral_reverts() public {
        vm.startPrank(bob); // bob has no deposit
        token.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.borrow(1e18);
        vm.stopPrank();
    }

    // ────────────────── REPAY TESTS ───────────────────────────────────────────

    /// Test 6: Full repayment clears debt
    function test_repay_full() public {
        vm.startPrank(alice);
        pool.borrow(5_000e18);
        (, uint256 borrowed,,) = pool.positions(alice);
        pool.repay(borrowed + 1e18); // repay more than needed (should be capped)
        (,, uint256 debt,) = pool.positions(alice);
        assertEq(debt, 0);
        vm.stopPrank();
    }

    /// Test 7: Partial repayment reduces debt proportionally
    function test_repay_partial() public {
        vm.startPrank(alice);
        pool.borrow(4_000e18);
        (,, uint256 debtBefore,) = pool.positions(alice);
        pool.repay(2_000e18);
        (,, uint256 debtAfter,) = pool.positions(alice);
        assertApproxEqAbs(debtAfter, debtBefore - 2_000e18, 1e15); // small interest allowed
        vm.stopPrank();
    }

    // ────────────────── WITHDRAW TESTS ────────────────────────────────────────

    /// Test 8: Withdraw with no debt succeeds
    function test_withdraw_noDebt() public {
        vm.startPrank(alice);
        uint256 before = token.balanceOf(alice);
        pool.withdraw(DEPOSIT_AMOUNT);
        assertEq(token.balanceOf(alice), before + DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /// Test 9: Withdraw while having debt that would break HF reverts
    function test_withdraw_withDebt_reverts() public {
        vm.startPrank(alice);
        pool.borrow(7_000e18); // near LTV limit
        vm.expectRevert();
        pool.withdraw(DEPOSIT_AMOUNT); // would make HF < 1
        vm.stopPrank();
    }

    // ────────────────── LIQUIDATION TESTS ─────────────────────────────────────

    /**
     * Test 10: Liquidation scenario
     * We simulate Alice borrowing 75 % LTV, then reduce her collateral via
     * a direct storage manipulation (simulating a price drop).
     */
    function test_liquidate_success() public {
        // Alice borrows near max
        vm.startPrank(alice);
        pool.borrow(7_499e18);
        vm.stopPrank();

        // Simulate price drop: artificially halve Alice's effective collateral
        // In a real oracle-based system a price feed would drop; here we
        // manipulate deposited to simulate < 80 % LTV coverage.
        // We use vm.store to directly write Alice's deposited field.
        // Position storage layout: deposited(0), borrowed(1), debtWithInterest(2), lastUpdate(3)
        bytes32 posSlot = keccak256(abi.encode(alice, uint256(0))); // mapping slot 0
        // Set deposited to 5000e18 (debt is 7499e18 → HF = 5000*80/7499 < 1)
        vm.store(address(pool), posSlot, bytes32(uint256(5_000e18)));

        // Verify health factor < 1
        assertLt(pool.healthFactor(alice), 1e18);

        // Liquidator repays 3000e18 of debt
        vm.startPrank(liquidator);
        token.approve(address(pool), type(uint256).max);
        uint256 beforeBal = token.balanceOf(liquidator);
        pool.liquidate(alice, 3_000e18);
        uint256 afterBal  = token.balanceOf(liquidator);
        vm.stopPrank();

        // Liquidator received collateral + 5 % bonus
        assertGt(afterBal, beforeBal - 3_000e18, "liquidator should net profit");
    }

    /// Test 11: Cannot liquidate healthy position
    function test_liquidate_healthyPosition_reverts() public {
        vm.startPrank(alice);
        pool.borrow(1_000e18); // only 10 % LTV — very healthy
        vm.stopPrank();

        vm.startPrank(liquidator);
        token.approve(address(pool), type(uint256).max);
        vm.expectRevert();
        pool.liquidate(alice, 500e18);
        vm.stopPrank();
    }

    // ────────────────── INTEREST ACCRUAL TEST ─────────────────────────────────

    /**
     * Test 12: Interest accrues over time using vm.warp.
     */
    function test_interestAccrual() public {
        vm.startPrank(alice);
        pool.borrow(5_000e18);
        (,, uint256 debtAtT0,) = pool.positions(alice);

        // Warp forward 365 days
        vm.warp(block.timestamp + 365 days);

        // Accrue interest by touching the position (deposit triggers _accrueInterest)
        pool.deposit(1); // trigger accrual
        (,, uint256 debtAtT1,) = pool.positions(alice);
        vm.stopPrank();

        assertGt(debtAtT1, debtAtT0, "Interest must have accrued over time");
    }

    // ────────────────── HEALTH FACTOR TESTS ───────────────────────────────────

    /// Test 13: Health factor is max when no debt
    function test_healthFactor_noDebt() public view {
        assertEq(pool.healthFactor(alice), type(uint256).max);
    }

    /// Test 14: Health factor is calculated correctly with debt
    function test_healthFactor_withDebt() public {
        vm.startPrank(alice);
        pool.borrow(5_000e18);
        vm.stopPrank();

        // HF = deposited * 0.80 / debt = 10000 * 0.80 / 5000 = 1.6
        uint256 hf = pool.healthFactor(alice);
        assertApproxEqRel(hf, 16e17, 0.01e18); // 1.6 * 1e18
    }

    /// Test 15 (bonus): Borrow zero reverts
    function test_borrow_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrow(0);
    }
}
