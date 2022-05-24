// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISwanSettings {
    function traderSet() external view returns (address);

    function lake() external view returns (address);

    function FEE_MULTIPLIER() external view returns (uint256);

    function treasury() external view returns (address);

    function monthlyFee() external view returns (uint256);

    function epochFee() external view returns (uint256);
}
