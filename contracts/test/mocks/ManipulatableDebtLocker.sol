// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { DebtLocker } from "../../DebtLocker.sol";

contract ManipulatableDebtLocker is DebtLocker {

    bytes32 constant FACTORY_SLOT = bytes32(0x7a45a402e4cb6e08ebc196f20f66d5d30e67285a2a8aa80503fa409e727a4af1);

    function setFactory(address factory_) external {
        _setSlotValue(FACTORY_SLOT, bytes32(uint256(uint160(factory_))));
    }

    function setPool(address pool_) external {
        _pool = pool_;
    }

}
