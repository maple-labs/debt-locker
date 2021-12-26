// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IMapleProxyFactory, MapleProxyFactory } from "../modules/maple-proxy-factory/contracts/MapleProxyFactory.sol";

import { IDebtLockerFactory } from "./interfaces/IDebtLockerFactory.sol";

/// @title Deploys DebtLocker proxy instances.
contract DebtLockerFactory is IDebtLockerFactory, MapleProxyFactory {

    uint8 public constant override factoryType = uint8(1);

    /// @param mapleGlobals_ The address of a Maple Globals contract.
    constructor(address mapleGlobals_) MapleProxyFactory(mapleGlobals_) {}

    function newLocker(address loan_) external override returns (address debtLocker_) {
        bytes memory arguments = abi.encode(loan_, msg.sender);

        bool success;
        ( success, debtLocker_ ) = _newInstance(defaultVersion, arguments);
        require(success, "DLF:NL:FAILED");

        emit InstanceDeployed(defaultVersion, debtLocker_, arguments);
    }

    /// @dev This function is disabled in favour of a PoolV1-compatible `newLocker` function.
    function createInstance(bytes calldata arguments_, bytes32 salt_)
        public override(IMapleProxyFactory, MapleProxyFactory) virtual returns (address instance_)
    {}

    /// @dev This function is disabled in since the PoolV1-compatible `newLocker` function is used instead of `createInstance`.
    function getInstanceAddress(bytes calldata arguments_, bytes32 salt_)
        public view override(IMapleProxyFactory, MapleProxyFactory) virtual returns (address instanceAddress_)
    {}

}
