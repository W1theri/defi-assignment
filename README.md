# DeFi Protocol Assignment
## BChT2 — Weeks 3–5: AMM / DEX Development

---

## Project Structure

```
defi-assignment/
├── src/
│   ├── ERC20Token.sol       — Base ERC-20 with mint/burn (Task 1)
│   ├── LPToken.sol          — Liquidity Provider token (Task 3)
│   ├── AMM.sol              — Constant-product AMM x*y=k (Task 3)
│   └── LendingPool.sol      — Overcollateralised lending pool (Task 5)
├── test/
│   ├── ERC20TokenTest.t.sol — Unit + fuzz + invariant tests (Task 1)
│   ├── AMMTest.t.sol        — AMM test suite 15+ cases (Task 3)
│   ├── LendingPoolTest.t.sol— Lending pool tests (Task 5)
│   └── ForkTest.t.sol       — Mainnet fork tests (Task 2)
├── script/
│   └── DeployAll.s.sol      — Deployment script (all contracts)
├── docs/
│   ├── AMM_Mathematical_Analysis.md  — Task 4
│   ├── FuzzVsUnitTesting.md          — Task 1 explanation
│   ├── ForkTestingExplanation.md     — Task 2 explanation
│   └── CICDPipelineExplanation.md    — Task 6 explanation
├── .github/workflows/
│   └── test.yml             — CI/CD pipeline (Task 6)
└── foundry.toml             — Foundry configuration
```

---

## Quick Start

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify
forge --version
```

### Setup

```bash
# Install forge-std library
forge install foundry-rs/forge-std

# Or clone with submodules
git clone --recursive <this-repo>
```

### Run All Tests

```bash
# Run all tests (excluding fork tests)
forge test --no-match-path "test/ForkTest.t.sol" -vvv

# Run with gas report
forge test --no-match-path "test/ForkTest.t.sol" --gas-report

# Run specific test file
forge test --match-path "test/AMMTest.t.sol" -vvv

# Run a single test
forge test --match-test "test_swap_AtoB" -vvv
```

### Fuzz & Invariant Tests

```bash
# Fuzz tests run automatically when test has parameters
forge test --match-test "testFuzz_" -vvv

# Invariant tests
forge test --match-contract "ERC20InvariantTest" -vvv
```

### Fork Tests

```bash
# Requires an RPC URL
export MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

forge test --match-path "test/ForkTest.t.sol" \
    --fork-url $MAINNET_RPC_URL -vvv
```

### Coverage Report

```bash
forge coverage --report summary
forge coverage --report lcov
genhtml lcov.info -o coverage-report/
```

### Deploy

```bash
# Local Anvil node
anvil &
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

forge script script/DeployAll.s.sol \
    --broadcast --fork-url http://localhost:8545
```

---

## Contract Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AMM POOL                                │
│                                                                 │
│   TokenA ────────────────────────────────────── TokenB          │
│      │           x * y = k (constant product)      │           │
│      │                                             │           │
│   reserveA                                      reserveB        │
│                                                                 │
│   addLiquidity() ──► mint LP tokens                             │
│   removeLiquidity() ──► burn LP tokens                          │
│   swap() ──► 0.3% fee stays in pool (k grows)                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     LENDING POOL                                │
│                                                                 │
│   deposit() ──► collateral stored                               │
│   borrow()  ──► max 75% LTV of collateral                       │
│   repay()   ──► reduce debt (+ accrued interest)                │
│   withdraw()──► only if health_factor > 1                       │
│   liquidate()──► when health_factor < 1 (+5% bonus)            │
│                                                                 │
│   Health Factor = (collateral × 0.80) / debt                   │
│   Interest Rate = 2% + 18% × utilisation (linear model)        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Test Coverage Summary

| Contract | Test File | Tests | Includes Fuzz? |
|---|---|---|---|
| ERC20Token | ERC20TokenTest.t.sol | 15 unit + 2 fuzz + 2 invariant | ✅ |
| AMM | AMMTest.t.sol | 16 unit + 1 fuzz | ✅ |
| LendingPool | LendingPoolTest.t.sol | 15 test cases | ❌ |
| Fork (mainnet) | ForkTest.t.sol | 3 fork tests | ❌ |

---

## Key Design Decisions

### AMM
- **MINIMUM_LIQUIDITY** (1000 wei) burned to `0xdead` on first deposit to prevent price manipulation via tiny deposits.
- **Geometric mean** for initial LP minting prevents front-running of first deposit.
- **k-invariant check** at end of swap reverts on any violation.

### LendingPool
- **Linear interest model**: `rate = 2% + 18% × utilisation`
- **Per-position accrual**: interest compounds only on user interaction (gas efficient).
- **Liquidation bonus**: 5% incentivises liquidators while limiting protocol loss.
- **Health Factor = 80% threshold** (above 75% LTV) gives a buffer before liquidation.
