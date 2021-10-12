// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IERC20 }      from "../../../modules/erc20/src/interfaces/IERC20.sol";
import { ERC20Helper } from "../../../modules/erc20-helper/src/ERC20Helper.sol";

import { IDebtLocker }        from "../../interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../interfaces/IDebtLockerFactory.sol";

contract MockLoan {

    uint256 public principalRequested;
    uint256 public claimableFunds;
    uint256 public principal;

    address public fundsAsset;
    address public collateralAsset;
    address public lender;

    constructor(uint256 principalRequested_, uint256 claimableFunds_, uint256 principal_, address fundsAsset_, address collateralAsset_) {
        principalRequested = principalRequested_;
        claimableFunds     = claimableFunds_;
        principal          = principal_;
        fundsAsset         = fundsAsset_;
        collateralAsset    = collateralAsset_;
    }

    function setClaimableFunds(uint256 claimableFunds_) external {
        claimableFunds = claimableFunds_;
    }

    function setLender(address lender_) external {
        lender = lender_;
    }

    function claimFunds(uint256 amount_, address destination_) public returns (bool success_) {
        claimableFunds -= amount_;
        return ERC20Helper.transfer(fundsAsset, destination_, amount_);
    }

    function repossess(address collateralAssetDestination_, address fundsAssetDestination_) internal virtual returns (bool success_) {
        claimableFunds = uint256(0);
        principal      = uint256(0);
        ERC20Helper.transfer(fundsAsset,      fundsAssetDestination_,      IERC20(fundsAsset).balanceOf(address(this)));
        ERC20Helper.transfer(collateralAsset, collateralAssetDestination_, IERC20(collateralAsset).balanceOf(address(this)));
        return true;
    }

    function changeParams(uint256 principalRequested_, uint256 claimableFunds_, uint256 principal_, address fundsAsset_, address collateralAsset_, address lender_) external {
        principalRequested = principalRequested_;
        claimableFunds     = claimableFunds_;
        principal          = principal_;
        fundsAsset         = fundsAsset_;
        collateralAsset    = collateralAsset_;
        lender             = lender_;
    }

    function putFunds(uint256 fundsTo_) external {
        principal -= fundsTo_;
    }

}

contract MockPool {

    address public dlFactory;

    constructor(address dlFactory_) {
        dlFactory = dlFactory_;
    }

    function createDebtLocker(address loan) public returns(address) {
        return IDebtLockerFactory(dlFactory).newLocker(loan);
    }

    function claim(address debtLocker) public returns(uint256[7] memory) {
        return IDebtLocker(debtLocker).claim();
    }

}
