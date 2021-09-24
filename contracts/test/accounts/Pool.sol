// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IDebtLocker }        from "../../interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../interfaces/IDebtLockerFactory.sol";

contract Pool {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function debtLockerFactory_newLocker(address factory, address loan) external returns (address) {
        return IDebtLockerFactory(factory).newLocker(loan);
    }

    function debtLocker_claim(address locker) external {
        IDebtLocker(locker).claim();
    }

    function debtLocker_triggerDefault(address locker) external {
        IDebtLocker(locker).triggerDefault();
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_debtLockerFactory_newLocker(address factory, address loan) external returns (bool ok) {
        (ok,) = factory.call(abi.encodeWithSelector(IDebtLockerFactory.newLocker.selector, loan));
    }

    function try_debtLocker_claim(address locker) external returns (bool ok) {
        (ok,) = locker.call(abi.encodeWithSelector(IDebtLocker.claim.selector));
    }

    function try_debtLocker_triggerDefault(address locker) external returns (bool ok) {
        (ok,) = locker.call(abi.encodeWithSelector(IDebtLocker.triggerDefault.selector));
    }

}
