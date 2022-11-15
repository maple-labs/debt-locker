// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { DebtLocker } from "../../contracts/DebtLocker.sol";

contract DebtLockerHarness is DebtLocker {

    /*************************/
    /*** Harness Functions ***/
    /*************************/

    function getGlobals() external view returns (address globals_) {
        globals_ = _getGlobals();
    }

    function getPoolDelegate() external view returns(address poolDelegate_) {
        poolDelegate_ = _getPoolDelegate();
    }

    function isLiquidationActive() external view returns (bool isLiquidationActive_) {
        isLiquidationActive_ = _isLiquidationActive();
    }

}
