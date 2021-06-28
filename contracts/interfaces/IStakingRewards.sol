// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

/// https://bscscan.com/address/0xc31b712bad4326227ee93e88c0e6b1839be35fc0#code

interface IStakingRewards {
    function stakeTo(uint256 amount, address _to) external;
    function notifyRewardAmount(uint256 reward) external;
}