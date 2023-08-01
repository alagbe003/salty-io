// SPDX-License-Identifier: BSL 1.1
pragma solidity =0.8.21;

import "./interfaces/IPriceFeed.sol";
import "../openzeppelin/access/Ownable.sol";
import "./interfaces/IPriceAggregator.sol";


// Compares three different price feeds to provide prices for BTC and ETH
// The three price feeds are used so that if one is updated by the DAO and it fails to work properly, the other two can still correctly report price.
// A singular PriceFeed can only be upgraded in this contract once every 35 days by default (to allow time to review performance of the most recently upgraded PriceFeed).
contract PriceAggregator is IPriceAggregator, Ownable
    {
    event PriceFeedError(address feed, string functionCall, bytes error);


	IPriceFeed public priceFeed1; // DualPriceFeed by default
	IPriceFeed public priceFeed2; // CoreChainlinkFeed by default
	IPriceFeed public priceFeed3; // CoreSaltyFeed by default

	// Cached for efficiency and only updated on performUpkeep
	// Allows liquidateUser() to consume less gas by using cached prices.
	uint256 private _lastPriceOnUpkeepBTC;
	uint256 private _lastPriceOnUpkeepETH;

	// The last time at which setPriceFeed was called
	uint256 public lastTimestampSetPriceFeed;

	// The maximum percent difference between two non-zero PriceFeed prices when determining price.
	// When the two closest PriceFeeds (out of the three) have prices further apart than this the aggregated price is considered invalid.
	// Range: 2% to 7% with an adjustment of .50%
	uint256 public maximumPriceFeedPercentDifferenceTimes1000 = 5000; // 5%

	// The required cooldown between calls to setPriceFeed.
	// Allows time to evaluate the performance of the recently update PriceFeed before other updates are made.
	// Range: 30 to 45 days with an adjustment of 5 days
	uint256 public setPriceFeedCooldown = 35 days;

	// The exponential average of the number of PriceFeeds that were used to aggregate prices on the last update.
	// Can detect recent errors or PriceFeed failures and encourage further investigation.
	uint256 public priceFeedInclusionAverage;


	function setInitialFeeds( IPriceFeed _priceFeed1, IPriceFeed _priceFeed2, IPriceFeed _priceFeed3 ) public
		{
		require( address(_priceFeed1) != address(0), "_priceFeed1 cannot be address(0)" );
		require( address(_priceFeed2) != address(0), "_priceFeed2 cannot be address(0)" );
		require( address(_priceFeed3) != address(0), "_priceFeed3 cannot be address(0)" );

		require( address(priceFeed1) == address(0), "setInitialFeeds() can only be called once" );

		priceFeed1 = _priceFeed1;
		priceFeed2 = _priceFeed2;
		priceFeed3 = _priceFeed3;
		}


	function setPriceFeed( uint256 priceFeedNum, IPriceFeed newPriceFeed ) public onlyOwner
		{
		uint256 elapsedSinceLastUpdate = block.timestamp - lastTimestampSetPriceFeed;

		// If the required cooldown is not met, simply return without reverting so that the original proposal can be finalized and new setPriceFeed proposals can be made.
		if ( elapsedSinceLastUpdate < setPriceFeedCooldown )
			return;

		if ( priceFeedNum == 1 )
			priceFeed1 = newPriceFeed;
		if ( priceFeedNum == 2 )
			priceFeed2 = newPriceFeed;
		if ( priceFeedNum == 3 )
			priceFeed3 = newPriceFeed;

		lastTimestampSetPriceFeed = block.timestamp;
		}


	function changeMaximumPriceFeedPercentDifferenceTimes1000(bool increase) public onlyOwner
		{
        if (increase)
            {
            if (maximumPriceFeedPercentDifferenceTimes1000 < 7000)
                maximumPriceFeedPercentDifferenceTimes1000 += 500;
            }
        else
            {
            if (maximumPriceFeedPercentDifferenceTimes1000 > 2000)
                maximumPriceFeedPercentDifferenceTimes1000 -= 500;
            }
		}


	function changeSetPriceFeedCooldown(bool increase) public onlyOwner
		{
        if (increase)
            {
            if (setPriceFeedCooldown < 45 days)
                setPriceFeedCooldown += 5 days;
            }
        else
            {
            if (setPriceFeedCooldown > 30 days)
                setPriceFeedCooldown -= 5 days;
            }
		}


	function _absoluteDifference( uint256 x, uint256 y ) internal pure returns (uint256)
		{
		if ( x > y )
			return x - y;

		return y - x;
		}


	function _aggregatePrices( uint256 price1, uint256 price2, uint256 price3 ) internal returns (uint256)
		{
		uint256 numNonZero;

		if (price1 > 0)
			numNonZero++;
		else
			price1 = type(uint256).max;

		if (price2 > 0)
			numNonZero++;
		else
			price2 = type(uint256).max;

		if (price3 > 0)
			numNonZero++;
		else
			price3 = type(uint256).max;

		// Update the priceFeedInclusionAverage
		if ( priceFeedInclusionAverage == 0 )
			priceFeedInclusionAverage = numNonZero;
		else
			{
			// Exponential average with a period of about 1000: 2 / (n+1)
			priceFeedInclusionAverage = ( priceFeedInclusionAverage * 499 + numNonZero * 1 ) / 500;
			}

		// If less than two price sources then return zero to indicate failure
		if ( numNonZero < 2 )
			return 0;

		uint256 diff12 = _absoluteDifference(price1, price2);
		uint256 diff13 = _absoluteDifference(price1, price3);
		uint256 diff23 = _absoluteDifference(price2, price3);

		uint256 priceA;
		uint256 priceB;

		if ( ( diff12 <= diff13 ) && ( diff12 <= diff23 ) )
			(priceA, priceB) = (price1, price2);
		else if ( ( diff13 <= diff12 ) && ( diff13 <= diff23 ) )
			(priceA, priceB) = (price1, price3);
		else if ( ( diff23 <= diff12 ) && ( diff23 <= diff13 ) )
			(priceA, priceB) = (price2, price3);

		uint256 averagePrice = ( priceA + priceB ) / 2;

		// If price sources are too far apart then return zero to indicate failure
		if (  (_absoluteDifference(priceA, priceB) * 100000) / averagePrice > maximumPriceFeedPercentDifferenceTimes1000 )
			return 0;

		return averagePrice;
		}


	function _updatePriceBTC() internal
		{
		uint256 price1;
		uint256 price2;
		uint256 price3;

		// Try blocks leave prices at zero (indicating failure) if anything foes wrong with them
 		try priceFeed1.getPriceBTC() returns (uint256 price)
			{
			price1 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceBTC", error);
			}

 		try priceFeed2.getPriceBTC() returns (uint256 price)
			{
			price2 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceBTC", error);
			}

 		try priceFeed3.getPriceBTC() returns (uint256 price)
			{
			price3 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceBTC", error);
			}

		_lastPriceOnUpkeepBTC = _aggregatePrices(price1, price2, price3);
		}


	function _updatePriceETH() internal
		{
		uint256 price1;
		uint256 price2;
		uint256 price3;

		// Try blocks leave prices at zero (indicating failure) if anything foes wrong with them
 		try priceFeed1.getPriceETH() returns (uint256 price)
			{
			price1 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceETH", error);
			}

 		try priceFeed2.getPriceETH() returns (uint256 price)
			{
			price2 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceETH", error);
			}

 		try priceFeed3.getPriceETH() returns (uint256 price)
			{
			price3 = price;
			}
		catch (bytes memory error)
			{
			emit PriceFeedError(address(priceFeed1), "getPriceETH", error);
			}

		_lastPriceOnUpkeepETH = _aggregatePrices(price1, price2, price3);
		}


	// Cache the current prices of BTC and ETH until the next performUpkeep
	// Publicly callable without restriction as the function simply updates the BTC and ETH prices as read from the PriceFeed (which is a trusted source of price).
	function performUpkeep() public
		{
		_updatePriceBTC();
		_updatePriceETH();
		}


	// === VIEWS ===

	// Return the BTC price (with 18 decimals) that was aggregated from the price feeds on the last performUpkeep.
	function getPriceBTC() public view returns (uint256)
		{
		require (_lastPriceOnUpkeepBTC != 0, "Invalid WBTC price" );

		return _lastPriceOnUpkeepBTC;
		}


	// Return the ETH price (with 18 decimals) that was aggregated from the price feeds on the last performUpkeep.
	function getPriceETH() public view returns (uint256)
		{
		require (_lastPriceOnUpkeepETH != 0, "Invalid WETH price" );

		return _lastPriceOnUpkeepETH;
		}
    }