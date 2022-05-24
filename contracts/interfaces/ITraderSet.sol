// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITraderSet {
    function traders(uint256) external view returns (address);

    function isTrader(address) external view returns (bool);

    function getTraderList() external view returns (address[] memory);

    function getTradersCount() external view returns (uint256);

    event TraderAdded(address trader);

    event TraderRemoved(address trader);
}
