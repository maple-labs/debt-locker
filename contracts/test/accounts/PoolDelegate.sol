// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IDebtLocker } from "../../interfaces/IDebtLocker.sol";

contract PoolDelegate {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function debtLocker_setAllowedSlippage(address debtLocker_, uint256 allowedSlippage_) external {
        IDebtLocker(debtLocker_).setAllowedSlippage(allowedSlippage_);
    }

    function debtLocker_setAuctioneer(address debtLocker_, address auctioneer_) external {
        IDebtLocker(debtLocker_).setAuctioneer(auctioneer_);
    }

    function debtLocker_setMinRatio(address debtLocker_, uint256 minRatio_) external {
        IDebtLocker(debtLocker_).setMinRatio(minRatio_);
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_debtLocker_setAllowedSlippage(address debtLocker_, uint256 allowedSlippage_) external returns (bool ok_) {
        ( ok_, ) = debtLocker_.call(abi.encodeWithSelector(IDebtLocker.setAllowedSlippage.selector, allowedSlippage_));
    }

    function try_debtLocker_setAuctioneer(address debtLocker_, address auctioneer_) external returns (bool ok_) {
        ( ok_, ) = debtLocker_.call(abi.encodeWithSelector(IDebtLocker.setAuctioneer.selector, auctioneer_));
    }

    function try_debtLocker_setMinRatio(address debtLocker_, uint256 minRatio_) external returns (bool ok_) {
        ( ok_, ) = debtLocker_.call(abi.encodeWithSelector(IDebtLocker.setMinRatio.selector, minRatio_));
    }

}
