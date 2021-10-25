// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLockerFactory is MapleProxyFactory {

    constructor(address mapleGlobals_) MapleProxyFactory(mapleGlobals_) {}

    uint8 public constant factoryType = uint8(1);

    function newLocker(address loan_) external returns (address debtLocker_) {
        bytes memory arguments = abi.encode(loan_, msg.sender);

        bool success_;
        ( success_, debtLocker_ ) = _newInstanceWithSalt(defaultVersion, arguments, keccak256(abi.encodePacked(msg.sender, nonceOf[msg.sender]++)));
        require(success_, "MPF:CI:FAILED");

        emit InstanceDeployed(defaultVersion, debtLocker_, arguments);
    }

}
