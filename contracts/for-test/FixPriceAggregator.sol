// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../interfaces/Ownable.sol";
import "../interfaces/AggregatorV3Interface.sol";

contract FixPriceAggregator is AggregatorV3Interface, Ownable {

    int256 public answer;
    uint8 public override decimals;
    string public override description;

    // function decimals() external view override returns (uint8){
    //     return 8;
    // }

    // function description() external view override returns (string memory){
    //     return "";
    // }

    function version() external view override returns (uint256){
        return 1;
    }

    constructor (int256 _answer , uint8 _decimals, string memory _desc) public {
        answer = _answer;
        decimals = _decimals;
        description = _desc;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId) external view override
    returns (
        uint80 roundId,
        int256 _answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ){
    }

    function latestRoundData() external view override
    returns (
        uint80 roundId,
        int256 _answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ){
        _answer = answer;
    }

    function setAnswer(int256 newAnswer) public onlyOwner {
        answer = newAnswer;
    }
}