// SPDX-License-Identifier: BUSL 1.1
pragma solidity =0.8.22;

import "forge-std/Test.sol";
import "../PriceAggregator.sol";


contract TestPriceAggregator is PriceAggregator
    {
    constructor(IPriceFeed priceFeed1, IPriceFeed priceFeed2, IPriceFeed priceFeed3)
    PriceAggregator(priceFeed1, priceFeed2, priceFeed3)
    	{
    	}

   	function absoluteDifference( uint256 x, uint256 y ) public pure returns (uint256)
		{
		return _absoluteDifference(x, y);
		}


	function aggregatePrices( uint256 price1, uint256 price2, uint256 price3 ) public view returns (uint256)
		{
		return _aggregatePrices(price1, price2, price3);
		}
    }