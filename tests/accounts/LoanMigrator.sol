// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IDebtLocker } from "../../contracts/interfaces/IDebtLocker.sol";

contract LoanMigrator {

    function debtLocker_setPendingLender(address debtLocker_, address newLender_) external {
        IDebtLocker(debtLocker_).setPendingLender(newLender_);
    }

    function try_debtLocker_setPendingLender(address debtLocker_, address newLender_) external returns (bool ok_) {
        ( ok_, ) = debtLocker_.call(abi.encodeWithSelector(IDebtLocker.setPendingLender.selector, newLender_));
    }

}
