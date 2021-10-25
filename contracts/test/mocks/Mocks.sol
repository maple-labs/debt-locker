// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IERC20 }             from "../../../modules/erc20/src/interfaces/IERC20.sol";
import { ILiquidatorLike }    from "../../../modules/liquidations/contracts/interfaces/Interfaces.sol";

import { ERC20Helper } from "../../../modules/erc20-helper/src/ERC20Helper.sol";
import { MockERC20 }   from "../../../modules/erc20/src/test/mocks/MockERC20.sol";

import { IDebtLocker }        from "../../interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "../../interfaces/IDebtLockerFactory.sol";

contract MockLoan {

    uint256 public principalRequested;
    uint256 public claimableFunds;
    uint256 public principal;

    address public fundsAsset;
    address public collateralAsset;
    address public lender;

    constructor(uint256 principalRequested_, address fundsAsset_, address collateralAsset_) {
        principalRequested = principalRequested_;
        principal          = principalRequested_;
        fundsAsset         = fundsAsset_;
        collateralAsset    = collateralAsset_;
    }

    function setLender(address lender_) external {
        lender = lender_;
    }

    function claimFunds(uint256 amount_, address destination_) public returns (bool success_) {
        claimableFunds -= amount_;
        return ERC20Helper.transfer(fundsAsset, destination_, amount_);
    }

    function repossess(address collateralAssetDestination_, address fundsAssetDestination_) external returns (uint256 collateralAssetAmount_, uint256 fundsAssetAmount_) {
        claimableFunds = uint256(0);
        principal      = uint256(0);

        collateralAssetAmount_ = IERC20(collateralAsset).balanceOf(address(this));
        fundsAssetAmount_      = IERC20(fundsAsset).balanceOf(address(this));

        require(ERC20Helper.transfer(collateralAsset, collateralAssetDestination_, collateralAssetAmount_), "MOCK_LOAN:R:CA_TRANSFER");
        require(ERC20Helper.transfer(fundsAsset,      fundsAssetDestination_,      fundsAssetAmount_),      "MOCK_LOAN:R:FA_TRANSFER");
    }

    function makePayment(uint256 principal_, uint256 interest_) external {
        principal      -= principal_;
        claimableFunds += principal_ + interest_;
        ERC20Helper.transferFrom(fundsAsset, msg.sender, address(this), principal_ + interest_);
    }

}

contract MockPoolFactory {

    address public globals;

    constructor(address globals_) {
        globals = globals_;
    }

    function createPool(address poolDelegate_) external returns (address) {
        return address(new MockPool(poolDelegate_));
    }

}

contract MockPool {

    address public poolDelegate;
    address public superFactory;

    constructor(address poolDelegate_) {
        poolDelegate = poolDelegate_;
        superFactory = msg.sender;
    }

    function createDebtLocker(address dlFactory, address loan) external returns (address) {
        return IDebtLockerFactory(dlFactory).newLocker(loan);
    }

    function claim(address debtLocker) external returns (uint256[7] memory) {
        return IDebtLocker(debtLocker).claim();
    }

    function triggerDefault(address debtLocker) external {
        return IDebtLocker(debtLocker).triggerDefault();
    }

}

contract MockLiquidationStrategy {

    function flashBorrowLiquidation(address lender_, uint256 swapAmount_, address collateralAsset_, address fundsAsset_) external {
        uint256 repaymentAmount = IDebtLocker(lender_).getExpectedAmount(swapAmount_);

        ERC20Helper.approve(fundsAsset_, lender_, repaymentAmount);

        ILiquidatorLike(lender_).liquidatePortion(
            swapAmount_,
            abi.encodeWithSelector(this.swap.selector, collateralAsset_, fundsAsset_, swapAmount_, repaymentAmount)
        );
    }

    function swap(address collateralAsset_, address fundsAsset_, uint256 swapAmount_, uint256 repaymentAmount_) external {
        MockERC20(fundsAsset_).mint(address(this), repaymentAmount_);
        MockERC20(collateralAsset_).burn(address(this), swapAmount_);
    }

}

contract MockGlobals {

    address public governor;

    mapping(address => uint256) assetPrices;

    constructor (address governor_) {
        governor = governor_;
    }

    function getLatestPrice(address asset_) external view returns (uint256 price_) {
        return assetPrices[asset_];
    }

    function setPrice(address asset_, uint256 price_) external {
        assetPrices[asset_] = price_;
    }

}
