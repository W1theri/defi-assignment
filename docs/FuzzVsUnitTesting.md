# Fuzz Testing vs Unit Testing
## When to Use Each — Task 1 Explanation

---

## Unit Testing

Unit tests are **deterministic, manually written test cases** where the developer
explicitly specifies both the input and the expected output.

### Strengths
- **Precision:** you can test exact boundary conditions (e.g., `totalSupply - 1`, `0`, `type(uint256).max`).
- **Documentation:** each test case communicates developer intent clearly.
- **Speed:** deterministic tests run fast and produce reproducible results in CI.
- **Error messages:** custom assertions produce informative failure reports.

### When to Use
Use unit tests when:
1. You know which edge cases matter (e.g., transfer to `address(0)`, overflow boundaries).
2. You are testing a specific business rule (e.g., "LTV must not exceed 75 %").
3. You need regression tests that will never change behaviour unexpectedly.
4. You are testing event emissions or exact error selectors.

### Example (from our ERC-20 suite)
```solidity
function test_transfer_zeroAddress_reverts() public {
    vm.prank(alice);
    vm.expectRevert(ERC20Token.ZeroAddress.selector);
    token.transfer(address(0), 1e18);
}
```

---

## Fuzz Testing

Fuzz testing (property-based testing) lets **Foundry generate thousands of random inputs**
automatically, checking that a high-level **property** holds for all of them.

### How Foundry Fuzz Testing Works
- Any test function with parameters is treated as a fuzz test.
- Foundry uses a coverage-guided mutational fuzzer (similar to AFL/libFuzzer).
- `vm.assume()` and `bound()` help constrain inputs to valid ranges.
- Default: 256 runs; production: 1 000–50 000 runs.

### Strengths
- **Discovers unexpected inputs** that a human developer never thought of.
- **Covers the entire input space** statistically, not just hand-picked points.
- **Invariant testing** (stateful fuzzing) finds violations across sequences of calls.
- Particularly powerful for **mathematical functions** like AMM swap formulas.

### When to Use
Use fuzz tests when:
1. You are testing a **mathematical property** (e.g., "k must never decrease after swap").
2. The function has a **continuous input space** (amounts, balances, timestamps).
3. You want to find **integer overflow/underflow** bugs.
4. You cannot enumerate all valid inputs manually.
5. You are writing **invariant tests** (global properties that must hold after any sequence of operations).

### Example (from our AMM test suite)
```solidity
function testFuzz_swap_kPreservation(uint256 amountIn) public {
    amountIn = bound(amountIn, 1e15, amm.reserveA() / 3);
    uint256 kBefore = amm.getK();
    amm.swap(address(tokenA), amountIn, 0);
    assertGe(amm.getK(), kBefore); // k must never decrease
}
```

---

## Summary: Decision Matrix

| Criterion | Unit Test | Fuzz Test |
|---|---|---|
| Input space | Small, discrete | Large, continuous |
| Developer effort | High (manual) | Low (property only) |
| Confidence | High for tested inputs | High across all inputs |
| Debugging ease | Easy (known input) | Harder (must replay seed) |
| Best for | Business rules, reverts | Math properties, invariants |
| CI speed | Fast | Configurable (1000 runs ≈ 1–5 s) |

**Best practice:** use both. Unit tests guard known requirements; fuzz tests guard against unknown edge cases. Together they give much higher assurance than either alone.
