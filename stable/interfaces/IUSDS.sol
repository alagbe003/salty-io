// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.12;

import "../../openzeppelin/token/ERC20/IERC20.sol";
import "./ICollateral.sol";
import "../../pools/interfaces/IPools.sol";

interface IUSDS is IERC20
	{
	function setCollateral( ICollateral _collateral ) external;
	function setPools( IPools _pools ) external;

	function mintTo( address wallet, uint256 amount ) external;
	function shouldBurnMoreUSDS( uint256 usdsToBurn ) external;
	}
