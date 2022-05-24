// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/ITraderSet.sol";
import "./interfaces/ISwanSettings.sol";

/**
 * @notice TraderSet contract is to add/remove traders
 */

contract TraderSet is Initializable, OwnableUpgradeable, ITraderSet {
    address[] public override traders;
    mapping(address => bool) public override isTrader;

    ISwanSettings public settings;

    function initialize() public initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function setSettings(ISwanSettings _settings) external onlyOwner {
        require(address(_settings) != address(0), "Invalid");

        settings = _settings;
    }

    function getTraderList() external view override returns (address[] memory) {
        return traders;
    }

    function getTradersCount() external view override returns (uint256) {
        return traders.length;
    }

    function addTrader(address trader) external onlyOwner {
        require(!isTrader[trader], "Already added");

        traders.push(trader);
        isTrader[trader] = true;

        emit TraderAdded(trader);
    }

    function removeTrader(address trader) external onlyOwner {
        require(isTrader[trader], "Not added yet");

        isTrader[trader] = false;

        uint256 index;
        for (; index < traders.length; index++) {
            if (traders[index] == trader) {
                break;
            }
        }

        if (index != traders.length - 1) {
            traders[index] = traders[traders.length - 1];
        }

        traders.pop();

        emit TraderRemoved(trader);
    }
}
