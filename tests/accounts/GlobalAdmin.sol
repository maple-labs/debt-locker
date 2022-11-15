// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { User as ProxyUser } from "../../modules/maple-proxy-factory/contracts/test/accounts/User.sol";

import { IDebtLocker, IMapleProxied } from "../../contracts/interfaces/IDebtLocker.sol";

contract GlobalAdmin is ProxyUser {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function debtLocker_upgrade(address debtLocker_, uint256 toVersion_, bytes memory arguments_) external {
        IDebtLocker(debtLocker_).upgrade(toVersion_, arguments_);
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_debtLocker_upgrade(address debtLocker_, uint256 toVersion_, bytes memory arguments_) external returns (bool ok_) {
        ( ok_, ) = debtLocker_.call(abi.encodeWithSelector(IMapleProxied.upgrade.selector, toVersion_, arguments_));
    }

}
