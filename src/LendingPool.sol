// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20Token.sol";

/**
 * @title LendingPool
 * @notice Simplified overcollateralised lending protocol.
 *
 *  Rules:
 *  ──────
 *  • Users deposit ERC-20 token as collateral.
 *  • Max borrow = 75 % of collateral value (LTV = 75 %).
 *  • Health factor = (collateral * liquidationThreshold) / debt.
 *  • Health factor < 1 → position can be liquidated.
 *  • Simple linear interest rate: BASE_RATE + SLOPE * utilisation.
 *  • Interest is tracked per-second via accrueInterest().
 *
 *  Note: For simplicity we use a single token as both collateral and
 *        borrowed asset (could be extended to two-token lending).
 */
contract LendingPool {
    // ── Constants ─────────────────────────────────────────────────────────────
    uint256 public constant LTV_NUMERATOR       = 75;   // 75 %
    uint256 public constant LTV_DENOMINATOR     = 100;

    uint256 public constant LIQ_THRESHOLD_NUM   = 80;   // 80 % — slightly above LTV
    uint256 public constant LIQ_THRESHOLD_DEN   = 100;

    uint256 public constant LIQ_BONUS           = 5;    // 5 % bonus for liquidators
    uint256 public constant LIQ_BONUS_DEN       = 100;

    // Annual interest rates stored as basis-points-per-second (ray arithmetic simplified)
    // BASE_RATE = 2 % APR, SLOPE = 18 % APR (at 100 % utilisation)
    // Per-second: 2 % / (365 * 86400) ≈ 635 (in 1e18 precision)
    uint256 public constant SECONDS_PER_YEAR    = 365 days;
    uint256 public constant BASE_RATE_PER_YEAR  = 2e16;   // 2 %  in 1e18
    uint256 public constant SLOPE_PER_YEAR      = 18e16;  // 18 % in 1e18
    uint256 public constant PRECISION           = 1e18;

    // ── Immutables ────────────────────────────────────────────────────────────
    ERC20Token public immutable token;

    // ── State ─────────────────────────────────────────────────────────────────
    struct Position {
        uint256 deposited;        // collateral in token units
        uint256 borrowed;         // principal borrowed
        uint256 debtWithInterest; // accrued debt (updated on interaction)
        uint256 lastUpdate;       // timestamp of last interest accrual
    }

    mapping(address => Position) public positions;

    uint256 public totalDeposits;
    uint256 public totalBorrows;

    // ── Events ────────────────────────────────────────────────────────────────
    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount, uint256 remaining);
    event Withdrawn(address indexed user, uint256 amount);
    event Liquidated(
        address indexed liquidator,
        address indexed borrower,
        uint256 debtRepaid,
        uint256 collateralSeized
    );

    // ── Errors ────────────────────────────────────────────────────────────────
    error ZeroAmount();
    error ExceedsLTV(uint256 requested, uint256 maxBorrow);
    error HealthFactorTooLow(uint256 healthFactor);
    error HealthFactorHealthy(uint256 healthFactor);
    error InsufficientCollateral();
    error RepaymentExceedsDebt();
    error NothingToWithdraw();
    error PoolInsolvent();

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(address _token) {
        token = ERC20Token(_token);
    }

    // ── External Functions ────────────────────────────────────────────────────

    /**
     * @notice Deposit `amount` tokens as collateral.
     */
    function deposit(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(msg.sender);

        token.transferFrom(msg.sender, address(this), amount);
        positions[msg.sender].deposited += amount;
        totalDeposits += amount;

        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Borrow `amount` tokens against deposited collateral.
     *         Reverts if resulting health factor would be < 1.
     */
    function borrow(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        uint256 maxBorrow = (pos.deposited * LTV_NUMERATOR) / LTV_DENOMINATOR;
        uint256 newDebt   = pos.debtWithInterest + amount;

        if (newDebt > maxBorrow) revert ExceedsLTV(amount, maxBorrow - pos.debtWithInterest);

        if (token.balanceOf(address(this)) < amount) revert PoolInsolvent();

        pos.borrowed         += amount;
        pos.debtWithInterest += amount;
        totalBorrows         += amount;

        token.transfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount);
    }

    /**
     * @notice Repay `amount` of outstanding debt.
     */
    function repay(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        uint256 debt = pos.debtWithInterest;

        // Cap repayment at full debt
        uint256 repayAmount = amount > debt ? debt : amount;

        token.transferFrom(msg.sender, address(this), repayAmount);

        pos.debtWithInterest -= repayAmount;
        if (pos.borrowed > repayAmount) {
            pos.borrowed -= repayAmount;
        } else {
            pos.borrowed = 0;
        }
        totalBorrows = totalBorrows > repayAmount ? totalBorrows - repayAmount : 0;

        emit Repaid(msg.sender, repayAmount, pos.debtWithInterest);
    }

    /**
     * @notice Withdraw collateral. Reverts if health factor would drop below 1.
     */
    function withdraw(uint256 amount) external {
        if (amount == 0) revert ZeroAmount();

        _accrueInterest(msg.sender);

        Position storage pos = positions[msg.sender];
        if (pos.deposited < amount) revert InsufficientCollateral();

        // Simulate post-withdrawal health factor
        uint256 newDeposit = pos.deposited - amount;
        if (pos.debtWithInterest > 0) {
            uint256 hf = _computeHealthFactor(newDeposit, pos.debtWithInterest);
            if (hf < PRECISION) revert HealthFactorTooLow(hf);
        }

        pos.deposited -= amount;
        totalDeposits -= amount;

        token.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Liquidate an undercollateralised position.
     *         Liquidator repays `debtAmount` and receives collateral + 5 % bonus.
     */
    function liquidate(address borrower, uint256 debtAmount) external {
        if (debtAmount == 0) revert ZeroAmount();

        _accrueInterest(borrower);

        Position storage pos = positions[borrower];
        uint256 hf = _computeHealthFactor(pos.deposited, pos.debtWithInterest);
        if (hf >= PRECISION) revert HealthFactorHealthy(hf);

        // Cap debtAmount at full debt
        uint256 repayAmount   = debtAmount > pos.debtWithInterest ? pos.debtWithInterest : debtAmount;
        uint256 collateralOut = (repayAmount * (100 + LIQ_BONUS)) / 100;

        if (collateralOut > pos.deposited) {
            collateralOut = pos.deposited; // bad debt scenario
        }

        token.transferFrom(msg.sender, address(this), repayAmount);

        pos.debtWithInterest -= repayAmount;
        pos.deposited        -= collateralOut;
        totalBorrows         = totalBorrows > repayAmount ? totalBorrows - repayAmount : 0;
        totalDeposits        = totalDeposits > collateralOut ? totalDeposits - collateralOut : 0;

        token.transfer(msg.sender, collateralOut);

        emit Liquidated(msg.sender, borrower, repayAmount, collateralOut);
    }

    // ── View Functions ────────────────────────────────────────────────────────

    /**
     * @notice Returns health factor of a position (scaled by 1e18).
     *         A value < 1e18 means the position can be liquidated.
     */
    function healthFactor(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debtWithInterest == 0) return type(uint256).max;
        return _computeHealthFactor(pos.deposited, pos.debtWithInterest);
    }

    /**
     * @notice Returns current utilisation ratio (scaled by 1e18).
     */
    function utilisation() public view returns (uint256) {
        if (totalDeposits == 0) return 0;
        return (totalBorrows * PRECISION) / totalDeposits;
    }

    /**
     * @notice Current annual borrow rate (scaled by 1e18).
     */
    function borrowRatePerYear() public view returns (uint256) {
        uint256 u = utilisation();
        return BASE_RATE_PER_YEAR + (SLOPE_PER_YEAR * u) / PRECISION;
    }

    /**
     * @notice Returns pending interest (not yet accrued) for a user.
     */
    function pendingInterest(address user) external view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debtWithInterest == 0 || pos.lastUpdate == 0) return 0;
        uint256 elapsed = block.timestamp - pos.lastUpdate;
        uint256 rate    = borrowRatePerYear();
        return (pos.debtWithInterest * rate * elapsed) / (SECONDS_PER_YEAR * PRECISION);
    }

    // ── Internal Functions ────────────────────────────────────────────────────

    /**
     * @dev Accrue simple interest on a user's debt.
     */
    function _accrueInterest(address user) internal {
        Position storage pos = positions[user];
        if (pos.lastUpdate == 0) {
            pos.lastUpdate = block.timestamp;
            return;
        }
        if (pos.debtWithInterest > 0) {
            uint256 elapsed  = block.timestamp - pos.lastUpdate;
            uint256 rate     = borrowRatePerYear();
            uint256 interest = (pos.debtWithInterest * rate * elapsed) / (SECONDS_PER_YEAR * PRECISION);
            pos.debtWithInterest += interest;
        }
        pos.lastUpdate = block.timestamp;
    }

    /**
     * @dev Health factor = (collateral * liquidationThreshold) / debt (scaled by 1e18).
     */
    function _computeHealthFactor(uint256 deposited, uint256 debt) internal pure returns (uint256) {
        if (debt == 0) return type(uint256).max;
        return (deposited * LIQ_THRESHOLD_NUM * PRECISION) / (debt * LIQ_THRESHOLD_DEN);
    }
}
