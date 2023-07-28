// SPDX-License-Identifier: BSL 1.1
pragma solidity =0.8.21;

import "forge-std/Test.sol";
import "../../root_tests/TestERC20.sol";
import "../../pools/Pools.sol";
import "../../Deployment.sol";
import "../../pools/PoolUtils.sol";
import "../ArbitrageSearch.sol";


contract TestArbitrage is Test, Deployment
	{
	IERC20 public tokenE;	// similar price to ETH
    IERC20 public tokenB; // similar price to BTC

	address public alice = address(0x1111);


	constructor()
		{
		// If $COVERAGE=yes, create an instance of the contract so that coverage testing can work
		// Otherwise, what is tested is the actual deployed contract on the blockchain (as specified in Deployment.sol)
		if ( keccak256(bytes(vm.envString("COVERAGE" ))) == keccak256(bytes("yes" )))
			{
			vm.prank(DEPLOYER);
			pools = new Pools(exchangeConfig, poolsConfig);

			pools.setDAO(dao);

			IArbitrageSearch arbitrageSearch = new ArbitrageSearch(pools, exchangeConfig);

			vm.prank(address(dao));
			poolsConfig.setArbitrageSearch( arbitrageSearch );
			}

		priceAggregator.performUpkeep();
		uint256 priceBTC = priceAggregator.getPriceBTC();
		uint256 priceETH = priceAggregator.getPriceETH();

		vm.startPrank(alice);
		tokenE = new TestERC20(18);
        tokenB = new TestERC20(18);
        vm.stopPrank();

        vm.startPrank(address(dao));
        poolsConfig.whitelistPool(tokenE, wbtc);
        poolsConfig.whitelistPool(tokenE, weth);
        poolsConfig.whitelistPool(tokenB, wbtc);
        poolsConfig.whitelistPool(tokenB, weth);
        vm.stopPrank();

		vm.startPrank(DEPLOYER);
		wbtc.transfer(alice, 1000000 *10**8);
		weth.transfer(alice, 1000000 ether);
		vm.stopPrank();

		vm.startPrank(alice);
		tokenE.approve( address(pools), type(uint256).max );
   		wbtc.approve( address(pools), type(uint256).max );
   		weth.approve( address(pools), type(uint256).max );

		pools.addLiquidity( tokenE, wbtc, 100 ether * priceBTC / priceETH, 100 *10**8, 0, block.timestamp );
		pools.addLiquidity( tokenE, weth, 1000 ether, 1000 ether, 0, block.timestamp );
		pools.addLiquidity( wbtc, weth, 1000 *10**8, 1000 ether * priceBTC / priceETH, 0, block.timestamp );

		pools.deposit( tokenE, 100 ether );

		// Initial transactions cost more gas
		pools.swap( tokenE, weth, 10 ether, 0, block.timestamp );
		pools.depositSwapWithdraw( weth, tokenE, 10 ether, 0, block.timestamp );

        vm.stopPrank();
		}


	function testGasDepositSwapWithdrawAndArbitrage() public
		{
		vm.startPrank(alice);
		pools.depositSwapWithdraw( tokenE, weth, 10 ether, 0, block.timestamp );
		}


	function testGasSwapAndArbitrage() public
		{
		vm.startPrank(alice);
		pools.swap( tokenE, weth, 10 ether, 0, block.timestamp );
		}


	function testDepositSwapWithdrawAndArbitrage() public
		{
		vm.startPrank(alice);
		uint256 amountOut = pools.depositSwapWithdraw( tokenE, weth, 10 ether, 0, block.timestamp );

//		console.log( "amountOut: ", amountOut );
//		console.log( "ending pools balance: ", pools.depositBalance( address(pools), weth ) );

		assertEq( amountOut, 9900223544648871298 );
		assertEq( pools.depositBalance( address(pools), weth ), 154279064741019952 );
		}
	}
