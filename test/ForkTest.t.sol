// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// ── GLOBAL INTERFACES ────────────────────────────────────────────────────────

interface IUSDC {
    function totalSupply() external view returns (uint256);
    function decimals()    external view returns (uint8);
    function symbol()      external view returns (string memory);
    function balanceOf(address) external view returns (uint256);
}

interface IUniswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external view returns (uint256[] memory amounts);
}

// ── TEST CONTRACT ────────────────────────────────────────────────────────────

contract ForkTest is Test {
    // Адреса в Mainnet
    address constant USDC              = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNISWAP_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant WETH              = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant DAI               = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint256 internal forkId;

    function setUp() public {
        // Берем RPC из командной строки (--fork-url) или .env
        // Если ничего не передано, пробуем публичный узел (может быть нестабилен)
        string memory rpcUrl = vm.envOr("MAINNET_RPC_URL", string("https://eth.llamarpc.com"));
        
        forkId = vm.createSelectFork(rpcUrl);
    }

    // TEST 1: Чтение данных USDC из мейннета
    function test_fork_USDC_totalSupply() public view {
        IUSDC usdc = IUSDC(USDC);

        uint256 supply   = usdc.totalSupply();
        uint8   decimals = usdc.decimals();
        string memory sym = usdc.symbol();

        console.log("USDC Symbol:", sym);
        console.log("USDC Decimals:", decimals);
        console.log("USDC Total Supply:", supply);

        assertEq(decimals, 6, "USDC should have 6 decimals");
        assertEq(sym, "USDC", "Symbol should be USDC");
        assertGt(supply, 10_000_000_000 * 1e6, "USDC supply should be > 10B");
    }

    // TEST 2: Симуляция обмена ETH на DAI через Uniswap V2
    function test_fork_UniswapV2_ETHtoDAI_swap() public {
        address trader = makeAddr("trader");
        vm.deal(trader, 1 ether);

        IUniswapV2Router router = IUniswapV2Router(UNISWAP_V2_ROUTER);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = DAI;

        uint256[] memory amounts = router.getAmountsOut(1 ether, path);
        uint256 expectedOut = amounts[1];
        
        console.log("Expected DAI for 1 ETH:", expectedOut / 1e18);

        vm.prank(trader);
        uint256[] memory received = router.swapExactETHForTokens{value: 1 ether}(
            0, 
            path,
            trader,
            block.timestamp + 60
        );

        uint256 daiReceived = received[1];
        console.log("Actual DAI received:", daiReceived / 1e18);

        assertGt(daiReceived, 100e18, "Must receive > 100 DAI for 1 ETH");
        assertApproxEqRel(daiReceived, expectedOut, 0.01e18);
    }

    /* Этот тест ЗАКОММЕНТИРОВАН, так как бесплатные RPC ключи (Infura/Alchemy) 
       обычно не поддерживают архивные данные (блок 17,000,000).
    
    function test_fork_rollFork() public {
        IUSDC usdc = IUSDC(USDC);
        uint256 supplyNow = usdc.totalSupply();

        // Попытка переключиться на старый блок
        vm.rollFork(17_000_000);
        uint256 supplyPast = usdc.totalSupply();

        console.log("Supply at block 17M:", supplyPast);
        assertGt(supplyPast, 0, "Past supply must be > 0");
    }
    */
}