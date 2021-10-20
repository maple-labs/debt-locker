// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.7;

import { IMapleProxyFactory } from "../../../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";

contract Governor {

    /************************/
    /*** Direct Functions ***/
    /************************/

    function debtLockerFactory_disableUpgradePath(address factory_, uint256 fromVersion_, uint256 toVersion_) external {
        IMapleProxyFactory(factory_).disableUpgradePath(fromVersion_, toVersion_);
    }

    function debtLockerFactory_enableUpgradePath(address factory_, uint256 fromVersion_, uint256 toVersion_, address migrator_) external {
        IMapleProxyFactory(factory_).enableUpgradePath(fromVersion_, toVersion_, migrator_);
    }

    function debtLockerFactory_registerImplementation(
        address factory_,
        uint256 version_,
        address implementationAddress_,
        address initializer_
    ) external {
        IMapleProxyFactory(factory_).registerImplementation(version_, implementationAddress_, initializer_);
    }

    function debtLockerFactory_setDefaultVersion(address factory_, uint256 version_) external {
        IMapleProxyFactory(factory_).setDefaultVersion(version_);
    }

    /*********************/
    /*** Try Functions ***/
    /*********************/

    function try_debtLockerFactory_disableUpgradePath(address factory_, uint256 fromVersion_,uint256 toVersion_) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(IMapleProxyFactory.disableUpgradePath.selector, fromVersion_, toVersion_));
    }

    function try_debtLockerFactory_enableUpgradePath(
        address factory_,
        uint256 fromVersion_,
        uint256 toVersion_,
        address migrator_
    ) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(IMapleProxyFactory.enableUpgradePath.selector, fromVersion_, toVersion_, migrator_));
    }

    function try_debtLockerFactory_registerImplementation(
        address factory_,
        uint256 version_,
        address implementationAddress_,
        address initializer_
    ) external returns (bool ok_) {
        ( ok_, ) = factory_.call(
            abi.encodeWithSelector(IMapleProxyFactory.registerImplementation.selector, version_, implementationAddress_, initializer_)
        );
    }

    function try_debtLockerFactory_setDefaultVersion(address factory_, uint256 version_) external returns (bool ok_) {
        ( ok_, ) = factory_.call(abi.encodeWithSelector(IMapleProxyFactory.setDefaultVersion.selector, version_));
    }

}