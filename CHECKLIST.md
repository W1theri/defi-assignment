# FINAL SUBMISSION CHECKLIST
## Assignment 2 — DeFi Protocol Development (AMM / DEX)

---

### ✅ PART 1 — Advanced Testing with Foundry

#### Task 1: Foundry Project Setup & Fuzz Testing
- [x] Foundry project initialized with `src/`, `test/`, `script/` directories
- [x] ERC-20 token contract: `src/ERC20Token.sol`
- [x] Standard unit tests (15 test cases): `test/ERC20TokenTest.t.sol`
      Covers: mint, transfer, approve, transferFrom, burn, edge cases, events
- [x] Fuzz tests for transfer: `testFuzz_transfer`, `testFuzz_mint`
- [x] Invariant tests (2): `invariant_totalSupplyMatchesSumOfBalances`, `invariant_noAddressExceedsTotalSupply`
- [x] Coverage report: `docs/test_output.txt` (97.4% line coverage)
- [x] Explanation (fuzz vs unit testing): `docs/FuzzVsUnitTesting.md`

#### Task 2: Fork Testing Against Mainnet
- [x] Fork test file: `test/ForkTest.t.sol`
- [x] Read USDC total supply from real USDC contract
- [x] Simulate Uniswap V2 ETH→DAI swap using real router
- [x] Explanation of `vm.createSelectFork` and `vm.rollFork`
- [x] Fork test output: `docs/test_output.txt`
- [x] Explanation of benefits/limitations: `docs/ForkTestingExplanation.md`

---

### ✅ PART 2 — AMM Development

#### Task 3: Constant Product AMM
- [x] `src/AMM.sol` — full constant-product AMM (x*y=k)
      - addLiquidity() with LP token minting
      - removeLiquidity() with LP token burning
      - swap() with 0.3% fee
      - getAmountOut() using constant-product formula
      - Events: LiquidityAdded, LiquidityRemoved, Swap
      - Slippage protection (minAmountOut parameter)
- [x] `src/LPToken.sol` — LP token contract
- [x] `src/ERC20Token.sol` — two ERC-20 token contracts (used as TokenA/TokenB)
- [x] Test suite: `test/AMMTest.t.sol` (17 tests including fuzz)
      - Add liquidity (first + subsequent providers)
      - Remove liquidity (partial and full)
      - Swap both directions (A→B and B→A)
      - k invariant verification after swaps
      - Slippage protection revert tests
      - Edge cases: zero amounts, invalid token, large price impact
      - Fuzz test on swap function
- [x] Gas report: `docs/test_output.txt`

#### Task 4: AMM Mathematical Analysis
- [x] `docs/AMM_Mathematical_Analysis.md` (3 pages)
      - Derivation of constant product formula
      - Effect of 0.3% fee on k invariant
      - Impermanent loss derivation + 2x price change example (−5.72%)
      - Price impact formula with numerical examples
      - Comparison with Uniswap V2 (missing features table)

---

### ✅ PART 3 — Lending Protocol Simulation

#### Task 5: Basic Lending Pool
- [x] `src/LendingPool.sol` — full lending protocol
      - deposit() — ERC-20 collateral deposit
      - borrow() — max 75% LTV
      - repay() — partial and full repayment
      - withdraw() — only if health factor > 1
      - liquidate() — with 5% bonus for liquidators
      - Health factor tracking
      - Linear interest rate model (2% + 18% × utilisation)
- [x] Test suite: `test/LendingPoolTest.t.sol` (15 tests)
      - Deposit and withdrawal flow
      - Borrow within/exceeding LTV limits
      - Repayment (partial and full)
      - Liquidation scenario (vm.store + vm.warp)
      - Interest accrual over time (vm.warp 365 days)
      - Edge cases: zero amounts, borrow with no collateral
- [x] Gas report: `docs/test_output.txt`
- [x] Workflow diagram: `diagrams/lending_pool_workflow.svg`

---

### ✅ PART 4 — CI/CD Pipeline

#### Task 6: GitHub Actions
- [x] `.github/workflows/test.yml` — 6-stage CI pipeline
      - Stage 1: Build (forge build --sizes)
      - Stage 2: Unit + fuzz + invariant tests (--gas-report)
      - Stage 3: Fork tests (conditional on MAINNET_RPC_URL)
      - Stage 4: Coverage (forge coverage --report lcov + Codecov upload)
      - Stage 5: Slither static analysis
      - Stage 6: Gas snapshot regression check (--tolerance 10)
- [x] Pipeline documentation: `docs/CICDPipelineExplanation.md`

---

### ✅ BONUS FILES
- [x] `script/DeployAll.s.sol` — deploy all contracts in one command
- [x] `foundry.toml` — full configuration (fuzz runs, RPC endpoints, profiles)
- [x] `.gitmodules` — forge-std dependency
- [x] `README.md` — full project documentation with quick start guide

---

### FILE COUNTS BY CATEGORY
| Category             | Files | Location               |
|----------------------|-------|------------------------|
| Smart contracts      | 4     | src/                   |
| Test suites          | 4     | test/                  |
| Deploy scripts       | 1     | script/                |
| CI/CD config         | 1     | .github/workflows/     |
| Documentation        | 5     | docs/                  |
| Diagrams             | 1     | diagrams/              |
| Config               | 3     | root                   |
| **TOTAL**            | **19**|                        |
