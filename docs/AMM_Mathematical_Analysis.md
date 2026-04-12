# AMM Mathematical Analysis
## DeFi Protocol Assignment — Task 4

---

## 1. Derivation of the Constant-Product Formula

### Core Invariant

The Automated Market Maker maintains the invariant:

```
x · y = k
```

where `x` and `y` are the reserves of two tokens A and B respectively, and `k` is a constant.

### Why It Works

When a trader sells `Δx` of token A to the pool, the pool's reserve of A becomes `x + Δx`. To preserve the invariant, the new reserve of B must satisfy:

```
(x + Δx) · y' = k = x · y
```

Solving for the output amount `Δy`:

```
y' = (x · y) / (x + Δx)
Δy = y - y' = y - (x · y)/(x + Δx)
   = y · Δx / (x + Δx)
```

This is the **output formula without fees**. The key insight is that as `Δx → ∞`, `Δy → y` — you can never drain the pool completely. This bounded liquidity property makes the AMM "always liquid" for any trade size.

### Price from the Invariant

The instantaneous price of token A in terms of B is the derivative:

```
P = -dy/dx = y/x
```

This is called the **marginal price** and equals the ratio of reserves — the same ratio set by the first liquidity provider.

---

## 2. Effect of the 0.3 % Fee on the Invariant k

### Fee Mechanics

With a 0.3 % fee, only 99.7 % of the input amount (`amountIn × 997/1000`) participates in the swap calculation:

```
amountOut = (amountIn × 997 × reserveOut) / (reserveIn × 1000 + amountIn × 997)
```

### K Grows Over Time

Without the fee, `k` stays exactly constant. With the fee, a small portion of each `amountIn` stays in the pool as "fee revenue". Concretely:

- Pre-swap:  k₀ = x · y
- Post-swap: k₁ = (x + Δx) · (y − Δy)

Because `Δy` is computed on `Δx × 0.997` rather than the full `Δx`, the pool retains the fee, and:

```
k₁ = k₀ × (1 + fee_portion)  >  k₀
```

This means that **k is a monotonically non-decreasing function of trades**. Liquidity providers earn fees as an increase in the value of `k` per LP token, which they realize when they remove liquidity.

---

## 3. Impermanent Loss

### Definition

Impermanent Loss (IL) is the difference between the value of tokens **held** in the AMM vs. simply **holding** the same tokens in a wallet (HODLing).

### Derivation

Let the initial price be `p₀ = y/x`. After a price change to `p₁`:

The pool rebalances to maintain `x · y = k`. The new reserves are:

```
x' = √(k / p₁)
y' = √(k · p₁)
```

Defining the price ratio `r = p₁ / p₀`:

```
Value in AMM   = 2 · √(k · p₁)            = 2 · y₀ · √r
Value if held  = x₀ · p₁ + y₀             = y₀ · (r + 1)
```

(expressing both in terms of token B, with `x₀ = y₀/p₀ = y₀`)

**IL formula:**

```
IL = 2√r / (r + 1)  −  1
```

### Numerical Example: 2× Price Change

If token A doubles in price: `r = 2`

```
IL = 2·√2 / (2 + 1) − 1
   = 2·1.4142 / 3 − 1
   = 2.8284 / 3 − 1
   = 0.9428 − 1
   ≈ −5.72 %
```

**Conclusion:** If the price of token A doubles relative to token B, LPs suffer approximately **5.72 % impermanent loss** compared to simply holding.

| Price change (r) | IL        |
|-----------------|-----------|
| 1.25× (25 % up) | −0.60 %   |
| 1.5×            | −2.02 %   |
| 2×              | −5.72 %   |
| 4×              | −20.0 %   |
| 10×             | −42.5 %   |

Loss is "impermanent" because if the price returns to `p₀`, IL = 0. It becomes permanent only when LPs exit at the diverged price.

---

## 4. Price Impact as a Function of Trade Size

### Price Impact Formula

Price impact measures how much a trade moves the market price. For a trade of size `Δx` into reserve `x`:

```
Price Impact ≈ Δx / (x + Δx)
```

More precisely, the **execution price** paid vs. the **spot price**:

```
Spot price          = y / x
Execution price     = Δy / Δx  =  y / (x + Δx)   (without fee)
Slippage (impact)   = 1 − execution/spot  =  Δx / (x + Δx)
```

### Examples (pool: x = 1 000 000, y = 500 000)

| Trade size Δx | Impact     | Output Δy  | Effective price |
|--------------|-----------|-----------|----------------|
| 1 000 (0.1 %) | 0.10 %    | 499.5      | 0.4995 B/A    |
| 10 000 (1 %) | 0.99 %    | 4 950.5    | 0.4950 B/A    |
| 100 000 (10 %)| 9.09 %   | 45 454     | 0.4545 B/A    |
| 500 000 (50 %)| 33.3 %   | 166 667    | 0.3333 B/A    |

Price impact grows super-linearly with trade size, which is why large trades experience significant "price slippage".

---

## 5. Comparison with Uniswap V2

Our AMM implements the core Uniswap V2 logic. Below are features **missing** from our implementation:

| Feature | Uniswap V2 | Our AMM |
|---|---|---|
| Flash loans (flash swaps) | ✅ | ❌ |
| Protocol fee switch (0.05 % to treasury) | ✅ | ❌ |
| TWAP oracle (price0CumulativeLast) | ✅ | ❌ |
| Permit (EIP-2612 gasless approval) | ✅ | ❌ |
| Factory + CREATE2 pair deployment | ✅ | ❌ |
| Safe transfer for non-standard ERC-20 | ✅ | ❌ |
| Skim / sync reserve recovery | ✅ | ❌ |
| Re-entrancy lock | ✅ | ❌ |
| Multi-hop routing (via router) | ✅ | ❌ |

**Most important missing feature:** The **TWAP oracle** is critical for DeFi composability — many protocols rely on Uniswap V2 price feeds. Without it, our AMM cannot serve as a price oracle for lending protocols, derivatives, etc.

**Second most important:** The **re-entrancy guard** (Uniswap uses a `locked` flag). Our AMM is vulnerable to re-entrant calls if integrated with malicious ERC-20 tokens.
