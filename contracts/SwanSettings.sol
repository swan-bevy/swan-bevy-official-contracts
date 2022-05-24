// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/ITraderSet.sol";
import "./interfaces/ISwanSettings.sol";

contract SwanSettings is Initializable, OwnableUpgradeable, ISwanSettings {
    uint256 public constant override FEE_MULTIPLIER = 1e3;

    address public override traderSet;
    address public override lake;

    address public override treasury; // fee sent
    uint256 public override monthlyFee;
    uint256 public override epochFee;

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function setTraderSet(address _traderSet) external onlyOwner {
        require(_traderSet != address(0), "Invalid");

        traderSet = _traderSet;
    }

    function setLake(address _lake) external onlyOwner {
        require(_lake != address(0), "Invalid");

        lake = _lake;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(address(_treasury) != address(0), "Invalid");

        treasury = _treasury;
    }

    function setMonthlyFee(uint256 _monthlyFee) external onlyOwner {
        require(_monthlyFee < FEE_MULTIPLIER, "Invalid");

        monthlyFee = _monthlyFee;
    }

    function setEpochFee(uint256 _epochFee) external onlyOwner {
        require(_epochFee < FEE_MULTIPLIER, "Invalid");

        epochFee = _epochFee;
    }
}
