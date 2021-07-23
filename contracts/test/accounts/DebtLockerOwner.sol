// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IDebtLocker } from "../../interfaces/IDebtLocker.sol";

import { DebtLockerFactory } from "../../DebtLockerFactory.sol";

contract DebtLockerOwner {

    function debtLockerFactory_newLocker(address factory, address loan) external returns (address) {
        return address(IDebtLocker(DebtLockerFactory(factory).newLocker(loan)));
    }

    function try_debtLockerFactory_newLocker(address factory, address loan) external returns (bool ok) {
        (ok,) = factory.call(abi.encodeWithSignature("newLocker(address)", loan));
    }

    function debtLocker_claim(address locker) external {
        IDebtLocker(locker).claim();
    }

    function try_debtLocker_claim(address locker) external returns (bool ok) {
        (ok,) = locker.call(abi.encodeWithSignature("claim()"));
    }

    function debtLocker_triggerDefault(address locker) external {
        IDebtLocker(locker).triggerDefault();
    }

    function try_debtLocker_triggerDefault(address locker) external returns (bool ok) {
        (ok,) = locker.call(abi.encodeWithSignature("triggerDefault()"));
    }

}
