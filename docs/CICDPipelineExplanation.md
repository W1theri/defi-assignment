# CI/CD Pipeline Documentation
## Task 6 — GitHub Actions for Smart Contracts

---

## Pipeline Overview

The pipeline defined in `.github/workflows/test.yml` runs automatically on every
`push` to `main`/`develop` and on every Pull Request. It consists of **6 stages**:

```
┌─────────┐     ┌─────────┐     ┌──────────┐     ┌──────────┐
│  Build  │────▶│  Test   │────▶│ Coverage │────▶│ Snapshot │
└─────────┘     └─────────┘     └──────────┘     └──────────┘
     │               │
     ├──────────────▶│ Fork Tests (parallel, if RPC key available)
     │
     └──────────────▶ Slither (parallel static analysis)
```

---

## Stage Descriptions

### Stage 1 — Build (`build`)
- Installs Foundry using the official `foundry-rs/foundry-toolchain` action.
- Runs `forge install` to pull git-submodule dependencies (e.g., forge-std).
- Compiles all contracts with `forge build --sizes` (reports contract bytecode sizes).
- Caches `out/` and `cache/` directories keyed by the hash of `.sol` files — subsequent
  stages skip recompilation if source is unchanged.

### Stage 2 — Unit & Fuzz Tests (`test`)
- Runs each test file separately so gas reports are scoped per-contract.
- `--gas-report` flag outputs a table of gas cost per function call.
- Gas reports are saved as pipeline **artifacts** (downloadable from GitHub Actions UI).
- Invariant tests run in a dedicated step with more verbose output (`-vvv`).

### Stage 3 — Fork Tests (`fork-tests`)
- Runs only if `MAINNET_RPC_URL` secret is configured in the GitHub repository.
- Executes `ForkTest.t.sol` against real mainnet state.
- Runs in **parallel** with Stage 2 to save total pipeline time.

### Stage 4 — Coverage (`coverage`)
- `forge coverage --report lcov` generates an LCOV-format coverage file.
- Uploads to **Codecov** (free tier) for a coverage badge and line-by-line HTML report.
- Also saves a `coverage_summary.txt` artifact with per-file percentages.

### Stage 5 — Slither Static Analysis (`slither`)
- Installs `slither-analyzer` (Python package).
- Runs Slither on each contract file separately.
- Findings are saved to `slither_report.txt` and uploaded as an artifact.
- Uses `|| true` so the pipeline does not fail on low-severity findings —
  in production, you would configure a severity threshold.

### Stage 6 — Gas Snapshot (`snapshot`)
- `forge snapshot` records baseline gas costs for all tests into `.gas-snapshot`.
- `forge snapshot --check --tolerance 10` compares against the stored baseline
  and **fails the pipeline if any function's gas cost regresses by more than 10 %**.
- This prevents accidental gas regressions from merging into `main`.

---

## How to Run Locally with `act`

```bash
# Install act (local GitHub Actions runner)
brew install act          # macOS
sudo apt install act      # Ubuntu

# Simulate the full pipeline
act push --secret MAINNET_RPC_URL=$MAINNET_RPC_URL

# Simulate only the test job
act push -j test
```

---

## Required GitHub Secrets

| Secret | Description |
|---|---|
| `MAINNET_RPC_URL` | Alchemy / Infura RPC URL for Ethereum mainnet |
| `ETHERSCAN_API_KEY` | For contract verification (optional for tests) |
