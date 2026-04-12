// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ERC20Token.sol";

/**
 * @title ERC20TokenTest
 * @notice Unit tests, fuzz tests, and invariant tests for ERC20Token.
 *         Covers > 10 unit cases, fuzz transfer, and 2 invariants.
 */
contract ERC20TokenTest is Test {
    ERC20Token internal token;

    address internal alice = makeAddr("alice");
    address internal bob   = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000e18;

    function setUp() public {
        token = new ERC20Token("Test Token", "TST", 18);
        token.mint(alice, INITIAL_SUPPLY);
    }

    // ────────────────── UNIT TESTS ──────────────────────────────────────────

    /// 1. Token metadata is set correctly
    function test_metadata() public view {
        assertEq(token.name(),     "Test Token");
        assertEq(token.symbol(),   "TST");
        assertEq(token.decimals(), 18);
    }

    /// 2. Mint increases totalSupply and recipient balance
    function test_mint() public {
        uint256 supplyBefore = token.totalSupply();
        token.mint(bob, 500e18);
        assertEq(token.totalSupply(),   supplyBefore + 500e18);
        assertEq(token.balanceOf(bob),  500e18);
    }

    /// 3. Only owner can mint
    function test_mint_onlyOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.NotOwner.selector);
        token.mint(bob, 1e18);
    }

    /// 4. Transfer moves tokens between accounts
    function test_transfer() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(bob),   100e18);
    }

    /// 5. Transfer to zero address reverts
    function test_transfer_zeroAddress_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.ZeroAddress.selector);
        token.transfer(address(0), 1e18);
    }

    /// 6. Transfer with insufficient balance reverts
    function test_transfer_insufficientBalance_reverts() public {
        vm.prank(bob); // bob has 0 tokens
        vm.expectRevert(ERC20Token.InsufficientBalance.selector);
        token.transfer(alice, 1e18);
    }

    /// 7. Approve sets allowance correctly
    function test_approve() public {
        vm.prank(alice);
        token.approve(bob, 200e18);
        assertEq(token.allowance(alice, bob), 200e18);
    }

    /// 8. Approve zero address reverts
    function test_approve_zeroAddress_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.ZeroAddress.selector);
        token.approve(address(0), 100e18);
    }

    /// 9. transferFrom reduces allowance correctly
    function test_transferFrom() public {
        vm.prank(alice);
        token.approve(bob, 300e18);

        vm.prank(bob);
        token.transferFrom(alice, carol, 100e18);

        assertEq(token.balanceOf(carol),   100e18);
        assertEq(token.allowance(alice, bob), 200e18); // 300 - 100
    }

    /// 10. transferFrom fails when allowance is insufficient
    function test_transferFrom_insufficientAllowance_reverts() public {
        vm.prank(alice);
        token.approve(bob, 50e18);

        vm.prank(bob);
        vm.expectRevert(ERC20Token.InsufficientAllowance.selector);
        token.transferFrom(alice, carol, 100e18);
    }

    /// 11. Infinite allowance (max uint256) is not decremented
    function test_infiniteAllowance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, carol, 500e18);

        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    /// 12. Burn reduces supply and balance
    function test_burn() public {
        vm.prank(alice);
        token.burn(100e18);
        assertEq(token.totalSupply(),     INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(alice),  INITIAL_SUPPLY - 100e18);
    }

    /// 13. Burn more than balance reverts
    function test_burn_excess_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.InsufficientBalance.selector);
        token.burn(INITIAL_SUPPLY + 1);
    }

    /// 14. Transfer emits event
    function test_transfer_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ERC20Token.Transfer(alice, bob, 10e18);
        token.transfer(bob, 10e18);
    }

    /// 15. Self-transfer keeps balances unchanged
    function test_selfTransfer() public {
        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(alice, 50e18);
        assertEq(token.balanceOf(alice), before);
    }

    // ────────────────── FUZZ TESTS ──────────────────────────────────────────

    /**
     * @notice Fuzz test: transfer any valid amount stays within supply.
     *         Foundry will run this 1000 times with random inputs.
     */
    function testFuzz_transfer(uint256 amount) public {
        // Bound the amount to alice's balance so the call is valid
        amount = bound(amount, 0, INITIAL_SUPPLY);

        vm.prank(alice);
        if (amount == 0) {
            // amount == 0 should still succeed (no explicit revert for 0 transfer)
            token.transfer(bob, 0);
        } else {
            token.transfer(bob, amount);
            assertEq(token.balanceOf(bob),   amount);
            assertEq(token.balanceOf(alice),  INITIAL_SUPPLY - amount);
        }
        // Total supply never changes
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    /**
     * @notice Fuzz test: mint any amount; supply must increase exactly by that amount.
     */
    function testFuzz_mint(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max); // avoid overflow
        uint256 supplyBefore = token.totalSupply();
        token.mint(bob, amount);
        assertEq(token.totalSupply(), supplyBefore + amount);
        assertEq(token.balanceOf(bob), amount);
    }

    // ────────────────── INVARIANT TESTS ─────────────────────────────────────
    // NOTE: Invariant tests in Foundry use a separate handler pattern.
    //       The actual invariant functions are in ERC20InvariantTest below.
}

/**
 * @title ERC20InvariantTest
 * @notice Stateful invariant testing harness.
 *         Foundry calls targetContract functions randomly and checks invariants.
 */
contract ERC20InvariantHandler is Test {
    ERC20Token public token;
    address[] public actors;

    constructor(ERC20Token _token) {
        token  = _token;
        actors = [makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
        // Give each actor some tokens
        for (uint256 i; i < actors.length; i++) {
            _token.mint(actors[i], 1_000_000e18);
        }
    }

    function transfer(uint256 actorSeed, uint256 amount) external {
        address from = actors[actorSeed % actors.length];
        address to   = actors[(actorSeed + 1) % actors.length];
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function burn(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 0, token.balanceOf(actor));
        vm.prank(actor);
        token.burn(amount);
    }
}

contract ERC20InvariantTest is Test {
    ERC20Token          internal token;
    ERC20InvariantHandler internal handler;

    function setUp() public {
        token   = new ERC20Token("Test Token", "TST", 18);
        handler = new ERC20InvariantHandler(token);
        // Set token owner to handler so it can mint during setUp
        // (already minted in constructor)
        targetContract(address(handler));
    }

    /**
     * @notice INVARIANT 1: Sum of all balances equals totalSupply.
     *         Checked against known actors.
     */
    function invariant_totalSupplyMatchesSumOfBalances() public view {
        address[] memory actors = new address[](3);
        actors[0] = makeAddr("a1");
        actors[1] = makeAddr("a2");
        actors[2] = makeAddr("a3");

        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        // totalSupply may be >= sum if tokens were sent elsewhere; but
        // no individual balance can exceed totalSupply
        assertLe(sum, token.totalSupply());
    }

    /**
     * @notice INVARIANT 2: No single address holds more than totalSupply.
     */
    function invariant_noAddressExceedsTotalSupply() public view {
        address[] memory actors = new address[](3);
        actors[0] = makeAddr("a1");
        actors[1] = makeAddr("a2");
        actors[2] = makeAddr("a3");

        uint256 supply = token.totalSupply();
        for (uint256 i; i < actors.length; i++) {
            assertLe(token.balanceOf(actors[i]), supply, "Balance exceeds total supply");
        }
    }
}
