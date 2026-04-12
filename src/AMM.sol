// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./LPToken.sol";
import "./ERC20Token.sol";

/**
 * @title AMM
 * @notice Constant-product Automated Market Maker (x * y = k).
 *
 *  Key design decisions:
 *  ─────────────────────
 *  • 0.3 % swap fee collected in the pool (adds to k over time).
 *  • First liquidity provider sets the initial price ratio.
 *  • Subsequent providers must supply tokens in the current ratio.
 *  • LP tokens are minted proportionally to the share of pool liquidity.
 *  • Slippage protection via `minAmountOut` parameter on swaps.
 */
contract AMM {
    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 public constant FEE_NUMERATOR   = 997;   // 1000 - 3  → 0.3 % fee
    uint256 public constant FEE_DENOMINATOR = 1000;
    uint256 private constant MINIMUM_LIQUIDITY = 1_000; // locked forever to avoid division by zero

    // ── Immutables ────────────────────────────────────────────────────────────
    ERC20Token public immutable tokenA;
    ERC20Token public immutable tokenB;
    LPToken    public immutable lpToken;

    // ── State ─────────────────────────────────────────────────────────────────
    uint256 public reserveA;
    uint256 public reserveB;

    // ── Events ────────────────────────────────────────────────────────────────
    event LiquidityAdded(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 lpMinted
    );
    event LiquidityRemoved(
        address indexed provider,
        uint256 amountA,
        uint256 amountB,
        uint256 lpBurned
    );
    event Swap(
        address indexed trader,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    // ── Errors ────────────────────────────────────────────────────────────────
    error ZeroAmount();
    error ZeroLiquidity();
    error SlippageExceeded(uint256 amountOut, uint256 minAmountOut);
    error InvalidToken();
    error InsufficientLPBalance();
    error KInvariantViolated();

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(address _tokenA, address _tokenB) {
        tokenA  = ERC20Token(_tokenA);
        tokenB  = ERC20Token(_tokenB);
        lpToken = new LPToken();
        lpToken.setMinter(address(this));
    }

    // ── External Functions ────────────────────────────────────────────────────

    /**
     * @notice Add liquidity to the pool.
     * @dev    First provider sets the price. Subsequent providers must match
     *         the current ratio; excess `amountBDesired` is returned implicitly
     *         (callers should set `amountBDesired` to maximum they are willing).
     * @param amountADesired  Amount of tokenA the caller wants to deposit.
     * @param amountBDesired  Maximum amount of tokenB the caller is willing to deposit.
     * @param amountAMin      Minimum tokenA actually deposited (slippage guard).
     * @param amountBMin      Minimum tokenB actually deposited (slippage guard).
     * @return amountA  Actual tokenA deposited.
     * @return amountB  Actual tokenB deposited.
     * @return liquidity  LP tokens minted.
     */
    function addLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (amountADesired == 0 || amountBDesired == 0) revert ZeroAmount();

        uint256 _reserveA = reserveA;
        uint256 _reserveB = reserveB;
        uint256 totalLP   = lpToken.totalSupply();

        if (_reserveA == 0 && _reserveB == 0) {
            // ── First deposit: use full desired amounts ──
            amountA = amountADesired;
            amountB = amountBDesired;
            // geometric mean for initial LP, minus MINIMUM_LIQUIDITY
            liquidity = _sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            // lock MINIMUM_LIQUIDITY forever
            lpToken.mintLP(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            // ── Subsequent deposit: maintain ratio ──
            uint256 amountBOptimal = (amountADesired * _reserveB) / _reserveA;
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert SlippageExceeded(amountBOptimal, amountBMin);
                amountA = amountADesired;
                amountB = amountBOptimal;
            } else {
                uint256 amountAOptimal = (amountBDesired * _reserveA) / _reserveB;
                if (amountAOptimal < amountAMin) revert SlippageExceeded(amountAOptimal, amountAMin);
                amountA = amountAOptimal;
                amountB = amountBDesired;
            }
            // LP proportional to share of pool
            liquidity = _min(
                (amountA * totalLP) / _reserveA,
                (amountB * totalLP) / _reserveB
            );
        }

        if (liquidity == 0) revert ZeroLiquidity();

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        reserveA = _reserveA + amountA;
        reserveB = _reserveB + amountB;

        lpToken.mintLP(msg.sender, liquidity);

        emit LiquidityAdded(msg.sender, amountA, amountB, liquidity);
    }

    /**
     * @notice Remove liquidity from the pool.
     * @param lpAmount    Amount of LP tokens to burn.
     * @param amountAMin  Minimum tokenA to receive (slippage guard).
     * @param amountBMin  Minimum tokenB to receive (slippage guard).
     * @return amountA  TokenA returned.
     * @return amountB  TokenB returned.
     */
    function removeLiquidity(
        uint256 lpAmount,
        uint256 amountAMin,
        uint256 amountBMin
    ) external returns (uint256 amountA, uint256 amountB) {
        if (lpAmount == 0) revert ZeroAmount();
        if (lpToken.balanceOf(msg.sender) < lpAmount) revert InsufficientLPBalance();

        uint256 totalLP = lpToken.totalSupply();
        amountA = (lpAmount * reserveA) / totalLP;
        amountB = (lpAmount * reserveB) / totalLP;

        if (amountA < amountAMin) revert SlippageExceeded(amountA, amountAMin);
        if (amountB < amountBMin) revert SlippageExceeded(amountB, amountBMin);

        lpToken.burnLP(msg.sender, lpAmount);
        reserveA -= amountA;
        reserveB -= amountB;

        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);

        emit LiquidityRemoved(msg.sender, amountA, amountB, lpAmount);
    }

    /**
     * @notice Swap an exact amount of one token for the other.
     * @param tokenIn     Address of the input token (must be tokenA or tokenB).
     * @param amountIn    Exact amount of tokenIn to swap.
     * @param minAmountOut  Minimum amount of output token (slippage protection).
     * @return amountOut  Amount of output token received.
     */
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (tokenIn != address(tokenA) && tokenIn != address(tokenB)) revert InvalidToken();

        bool aToB = (tokenIn == address(tokenA));

        uint256 _reserveIn  = aToB ? reserveA : reserveB;
        uint256 _reserveOut = aToB ? reserveB : reserveA;

        amountOut = getAmountOut(amountIn, _reserveIn, _reserveOut);

        if (amountOut < minAmountOut) revert SlippageExceeded(amountOut, minAmountOut);

        // Pull tokenIn from caller
        ERC20Token(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Update reserves
        if (aToB) {
            reserveA += amountIn;
            reserveB -= amountOut;
            tokenB.transfer(msg.sender, amountOut);
        } else {
            reserveB += amountIn;
            reserveA -= amountOut;
            tokenA.transfer(msg.sender, amountOut);
        }

        // Verify k has not decreased (fee causes k to grow)
        uint256 kBefore = _reserveIn  * _reserveOut;
        uint256 kAfter  = reserveA    * reserveB;
        if (kAfter < kBefore) revert KInvariantViolated();

        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }

    // ── View Functions ────────────────────────────────────────────────────────

    /**
     * @notice Compute output amount given input amount and reserves.
     *         Applies 0.3 % fee: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert ZeroLiquidity();

        uint256 amountInWithFee = amountIn * FEE_NUMERATOR;
        uint256 numerator       = amountInWithFee * reserveOut;
        uint256 denominator     = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @notice Returns current pool price as tokenB per tokenA (18 decimals).
     */
    function getPrice() external view returns (uint256) {
        if (reserveA == 0) revert ZeroLiquidity();
        return (reserveB * 1e18) / reserveA;
    }

    /**
     * @notice Returns the current k value.
     */
    function getK() external view returns (uint256) {
        return reserveA * reserveB;
    }

    // ── Internal Helpers ──────────────────────────────────────────────────────

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
