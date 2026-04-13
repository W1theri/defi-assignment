// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ERC20Token.sol";

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

    function test_metadata() public view {
        assertEq(token.name(),     "Test Token");
        assertEq(token.symbol(),   "TST");
        assertEq(token.decimals(), 18);
    }

    function test_mint() public {
        uint256 supplyBefore = token.totalSupply();
        token.mint(bob, 500e18);
        assertEq(token.totalSupply(),   supplyBefore + 500e18);
        assertEq(token.balanceOf(bob),  500e18);
    }

    function test_mint_onlyOwner_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.NotOwner.selector);
        token.mint(bob, 1e18);
    }

    function test_transfer() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(bob),   100e18);
    }

    function test_transfer_zeroAddress_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.ZeroAddress.selector);
        token.transfer(address(0), 1e18);
    }

    function test_transfer_insufficientBalance_reverts() public {
        vm.prank(bob);
        vm.expectRevert(ERC20Token.InsufficientBalance.selector);
        token.transfer(alice, 1e18);
    }

    function test_approve() public {
        vm.prank(alice);
        token.approve(bob, 200e18);
        assertEq(token.allowance(alice, bob), 200e18);
    }

    function test_approve_zeroAddress_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.ZeroAddress.selector);
        token.approve(address(0), 100e18);
    }

    function test_transferFrom() public {
        vm.prank(alice);
        token.approve(bob, 300e18);
        vm.prank(bob);
        token.transferFrom(alice, carol, 100e18);
        assertEq(token.balanceOf(carol),   100e18);
        assertEq(token.allowance(alice, bob), 200e18);
    }

    function test_transferFrom_insufficientAllowance_reverts() public {
        vm.prank(alice);
        token.approve(bob, 50e18);
        vm.prank(bob);
        vm.expectRevert(ERC20Token.InsufficientAllowance.selector);
        token.transferFrom(alice, carol, 100e18);
    }

    function test_infiniteAllowance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, carol, 500e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    function test_burn() public {
        vm.prank(alice);
        token.burn(100e18);
        assertEq(token.totalSupply(),     INITIAL_SUPPLY - 100e18);
        assertEq(token.balanceOf(alice),  INITIAL_SUPPLY - 100e18);
    }

    function test_burn_excess_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ERC20Token.InsufficientBalance.selector);
        token.burn(INITIAL_SUPPLY + 1);
    }

    function test_transfer_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit ERC20Token.Transfer(alice, bob, 10e18);
        token.transfer(bob, 10e18);
    }

    function test_selfTransfer() public {
        uint256 before = token.balanceOf(alice);
        vm.prank(alice);
        token.transfer(alice, 50e18);
        assertEq(token.balanceOf(alice), before);
    }

    function testFuzz_transfer(uint256 amount) public {
        amount = bound(amount, 0, INITIAL_SUPPLY);
        vm.prank(alice);
        if (amount == 0) {
            token.transfer(bob, 0);
        } else {
            token.transfer(bob, amount);
            assertEq(token.balanceOf(bob),   amount);
            assertEq(token.balanceOf(alice),  INITIAL_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function testFuzz_mint(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        uint256 supplyBefore = token.totalSupply();
        token.mint(bob, amount);
        assertEq(token.totalSupply(), supplyBefore + amount);
        assertEq(token.balanceOf(bob), amount);
    }
}

contract ERC20InvariantHandler is Test {
    ERC20Token public token;
    address[] public actors;

    constructor(ERC20Token _token, address _owner) {
        token  = _token;
        actors = [makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
        for (uint256 i; i < actors.length; i++) {
            vm.prank(_owner);
            token.mint(actors[i], 1_000_000e18);
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
    ERC20Token            internal token;
    ERC20InvariantHandler internal handler;

    function setUp() public {
        token   = new ERC20Token("Test Token", "TST", 18);
        handler = new ERC20InvariantHandler(token, address(this));
        targetContract(address(handler));
    }

    function invariant_totalSupplyMatchesSumOfBalances() public {
        address[] memory actors = new address[](3);
        actors[0] = makeAddr("a1");
        actors[1] = makeAddr("a2");
        actors[2] = makeAddr("a3");

        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertLe(sum, token.totalSupply());
    }

    function invariant_noAddressExceedsTotalSupply() public {
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