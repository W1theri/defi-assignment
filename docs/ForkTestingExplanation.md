# Fork Testing with Foundry
## Benefits and Limitations — Task 2 Explanation

---

## What is Fork Testing?

Fork testing creates a **local copy of a live blockchain state** at a specific block height.
Your tests run against real deployed contracts (USDC, Uniswap, Aave, etc.) without
spending real gas or modifying mainnet state.

---

## Key Foundry Cheatcodes

### `vm.createSelectFork(rpcUrl)`
```solidity
uint256 forkId = vm.createSelectFork("https://eth-mainnet.alchemyapi.io/v2/KEY");
```
- Connects to a remote node via RPC.
- Snapshots the state at the **latest block**.
- Returns a `forkId` that can be switched to later with `vm.selectFork(forkId)`.

### `vm.createSelectFork(rpcUrl, blockNumber)`
```solidity
uint256 forkId = vm.createSelectFork(rpcUrl, 17_000_000);
```
- Same as above but pins state to a **specific block** — enables historical replay.

### `vm.rollFork(blockNumber)`
```solidity
vm.rollFork(18_500_000); // fast-forward the active fork
```
- Changes the active fork's block number **without** creating a new fork.
- Very useful for testing time-sensitive logic (e.g., "what happens if price drops next block?").

### Multiple Forks
```solidity
uint256 forkA = vm.createFork(rpcA); // mainnet
uint256 forkB = vm.createFork(rpcB); // Arbitrum
vm.selectFork(forkA);  // switch between chains mid-test
```

---

## Benefits of Fork Testing

| Benefit | Description |
|---|---|
| **Real contract state** | Tests against actual deployed bytecode — no need to mock Uniswap, Chainlink, etc. |
| **Integration testing** | Validates your contract works with real DeFi protocols in realistic conditions. |
| **Historical replay** | Pin to any past block to reproduce a specific exploit or state. |
| **No gas cost** | Runs locally — no ETH spent. |
| **Speed** | Much faster than deploying to a public testnet. |
| **Composability testing** | Test how your protocol interacts with the full DeFi ecosystem. |

---

## Limitations of Fork Testing

| Limitation | Description |
|---|---|
| **RPC dependency** | Requires a paid RPC provider (Alchemy, Infura). Free tiers have rate limits. |
| **Slower than unit tests** | Each test that touches forked state makes RPC calls; cold runs are 5–20× slower. |
| **Non-deterministic** | If you fork "latest", the block advances between runs — tests may behave differently. |
| **RPC caching needed** | Without `--fork-block-number` pinning, CI results can vary. Pin the block for reproducibility. |
| **Mainnet state changes** | A protocol upgrade can silently break your tests if you don't pin block numbers. |
| **Private state** | You can read public state but cannot easily test permissioned functions (e.g., Compound admin). |

---

## Best Practices

1. **Always pin `block_number`** in CI for reproducible runs.
2. Use `vm.deal(address, amount)` to give test addresses ETH without using real wallets.
3. Use `vm.store(contract, slot, value)` to manipulate storage for edge-case simulation.
4. Cache fork state with Foundry's `--fork-cache-path` to speed up repeated runs.
5. Keep fork tests in a separate file/folder and run them conditionally in CI (only when `MAINNET_RPC_URL` is set).
