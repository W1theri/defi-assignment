// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ERC20Token.sol";

/**
 * @title LPToken
 * @notice Liquidity Provider token issued by the AMM.
 *         Only the AMM contract (minter) can mint / burn LP tokens.
 */
contract LPToken is ERC20Token {
    address public minter;

    error NotMinter();

    constructor() ERC20Token("AMM LP Token", "AMM-LP", 18) {
        minter = msg.sender; // will be re-set to AMM address after deploy
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    /**
     * @notice Set the authorised minter (should be called by AMM during init).
     */
    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    /**
     * @notice Mint LP tokens — only AMM can call this.
     */
    function mintLP(address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /**
     * @notice Burn LP tokens — only AMM can call this.
     */
    function burnLP(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }
}
