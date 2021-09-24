// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IDebtLocker }        from "../../interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../interfaces/IDebtLockerFactory.sol";

contract Pool {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function debtLockerFactory_newLocker(address factory_, address loan_) external returns (address locker_) {
        return IDebtLockerFactory(factory_).newLocker(loan_);
    }

    function debtLocker_claim(address locker_) external {
        IDebtLocker(locker_).claim();
    }

    function debtLocker_triggerDefault(address locker_) external {
        IDebtLocker(locker_).triggerDefault();
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_debtLockerFactory_newLocker(address factory_, address loan_) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(IDebtLockerFactory.newLocker.selector, loan_));
    }

    function try_debtLocker_claim(address locker_) external returns (bool ok_) {
        ( ok_, ) = locker_.call(abi.encodeWithSelector(IDebtLocker.claim.selector));
    }

    function try_debtLocker_triggerDefault(address locker_) external returns (bool ok_) {
        ( ok_, ) = locker_.call(abi.encodeWithSelector(IDebtLocker.triggerDefault.selector));
    }

}
