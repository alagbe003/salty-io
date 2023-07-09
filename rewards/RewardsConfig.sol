//// SPDX-License-Identifier: BSL 1.1
//pragma solidity ^0.8.12;
//
//import "../openzeppelin/access/Ownable.sol";
//import "./interfaces/IRewardsConfig.sol";
//
//
//// Contract owned by the DAO with parameters modifiable only by the DAO
//contract RewardsConfig is IRewardsConfig, Ownable
//    {
//	// The weekly percent of SALT emissions that will be distributed from Emissions.sol to the Liquidity and xSALT Holder Reward Emitters.
//	// Range: 0.25% to 1.0% with an adjustment of 0.25%
//	uint256 public emissionsWeeklyPercentTimes1000 = 500;  // Defaults to 0.50% with a 1000x multiplier
//
//	// By default, xSALT holders get 50% and liquidity providers get 50% of emissions
//	// Range: 25% to 75% with an adjustment of 5%
//    uint256 public emissionsXSaltHoldersPercent = 50;
//
//	// The target daily percent rewards emitter distribution (from the SALT balance in each emitter contract).
//	// Rewards Emitters distributed SALT rewards over time to the SharedRewards contracts where the rewards can be claimed by users.
//	// Range: .50% to 2.5% with an adjustment of 0.25%
//	uint256 public rewardsEmitterDailyPercentTimes1000 = 1000;  // Defaults to 1.0% with a 1000x multiplier
//
//
//	function changeRewardsEmitterDailyPercent(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (rewardsEmitterDailyPercentTimes1000 < 2500)
//                rewardsEmitterDailyPercentTimes1000 = rewardsEmitterDailyPercentTimes1000 + 250;
//            }
//        else
//            {
//            if (rewardsEmitterDailyPercentTimes1000 > 500)
//                rewardsEmitterDailyPercentTimes1000 = rewardsEmitterDailyPercentTimes1000 - 250;
//            }
//        }
//
//	function changeEmissionsWeeklyPercent(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (emissionsWeeklyPercentTimes1000 < 1000)
//                emissionsWeeklyPercentTimes1000 = emissionsWeeklyPercentTimes1000 + 250;
//            }
//        else
//            {
//            if (emissionsWeeklyPercentTimes1000 > 250)
//                emissionsWeeklyPercentTimes1000 = emissionsWeeklyPercentTimes1000 - 250;
//            }
//        }
//
//
//	function changeXSaltHoldersPercent(bool increase) public onlyOwner
//        {
//        if (increase)
//            {
//            if (emissionsXSaltHoldersPercent < 75)
//                emissionsXSaltHoldersPercent = emissionsXSaltHoldersPercent + 5;
//            }
//        else
//            {
//            if (emissionsXSaltHoldersPercent > 25)
//                emissionsXSaltHoldersPercent = emissionsXSaltHoldersPercent - 5;
//            }
//        }
//    }