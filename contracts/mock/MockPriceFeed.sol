// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract MockPriceFeed {
    int256 public price;

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, price, 0, 0, 0);
    }

    function setPrice(int256 _price) external {
        price = _price;
    }
}
