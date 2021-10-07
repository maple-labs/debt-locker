// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IDebtLockerFactory } from "./interfaces/IDebtLockerFactory.sol";

import { DebtLocker } from "./DebtLocker.sol";

/// @title DebtLockerFactory instantiates DebtLockers.
contract DebtLockerFactory is IDebtLockerFactory {

    mapping(address => address) public override owner;     // Owners of respective DebtLockers.
    mapping(address => bool)    public override isLocker;  // True only if a DebtLocker was created by this factory.

    uint8 public override constant factoryType = 1;

    function newLocker(address loan_) external override returns (address debtLocker_) {
        debtLocker_           = address(new DebtLocker(loan_, msg.sender));
        owner[debtLocker_]    = msg.sender;
        isLocker[debtLocker_] = true;

        emit DebtLockerCreated(msg.sender, debtLocker_, loan_);
    }

}
