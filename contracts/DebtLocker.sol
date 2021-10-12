// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { Liquidator }  from "../modules/liquidations/contracts/Liquidator.sol";
import { ERC20Helper } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IDebtLocker } from "./interfaces/IDebtLocker.sol";

import { IERC20Like, IMapleGlobalsLike, IMapleLoanLike, IPoolLike, IPoolFactoryLike }  from "./interfaces/Interfaces.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLocker is IDebtLocker {

    address public override immutable factory;
    address public override immutable loan;
    address public override immutable pool;

    uint256 public override allowedSlippage;
    uint256 public override minRatio;
    uint256 public override principalRemainingAtLastClaim;

    address public override liquidator;


    constructor(address loan_, address pool_) {
        factory = msg.sender;
        loan    = loan_;
        pool    = pool_;
        
        principalRemainingAtLastClaim = IMapleLoanLike(loan_).principalRequested();
    }

    /*******************************/
    /*** Pool Delegate Functions ***/
    /*******************************/

    function claim() external override returns (uint256[7] memory details_) {
        require(_isPool(msg.sender), "DL:C:NOT_POOL");

        // Get loan state variables we need
        uint256 claimableFunds = IMapleLoanLike(loan).claimableFunds();
        require(claimableFunds > uint256(0), "DL:C:NOTHING_TO_CLAIM");

        uint256 currentPrincipalRemaining = IMapleLoanLike(loan).principal();

        // Determine how much of `claimableFunds` is principal
        uint256 principalPortion = principalRemainingAtLastClaim - currentPrincipalRemaining;

        // Send funds to pool
        IMapleLoanLike(loan).claimFunds(claimableFunds, pool);

        // Update state variables
        principalRemainingAtLastClaim = currentPrincipalRemaining;

        // Set return values
        // Note - All fees get deducted and transferred during `loan.fundLoan()` that omits the need to
        // return the fees distribution to the pool.
        details_[0] = claimableFunds;
        details_[1] = claimableFunds - principalPortion;
        details_[2] = principalPortion;
    }

    function triggerDefault() external override {
        require(_isPool(msg.sender), "DL:TD:NOT_PD");

        // Repossess collateral and funds from Loan
        ( uint256 collateralAssetAmount, ) = IMapleLoanLike(loan).repossess(address(this), address(this));

        address collateralAsset = IMapleLoanLike(loan).collateralAsset();
        address fundsAsset      = IMapleLoanLike(loan).fundsAsset();
        
        if (collateralAsset == fundsAsset) return;

        // Deploy Liquidator contract and transfer collateral
        liquidator = address(new Liquidator(address(this), collateralAsset, fundsAsset, address(this)));
        require(ERC20Helper.transfer(collateralAsset, address(liquidator), collateralAssetAmount), "DL:TD:TRANSFER");
    }

    function setAuctioneer(address auctioneer_) external override {
        require(_isPoolDelegate(msg.sender), "DL:SA:NOT_PD");
        Liquidator(liquidator).setAuctioneer(auctioneer_);
    }

    // TODO: Discuss pros/cons of calculating balance in function instead of using amount param.
    function pullFunds(address token_, address destination_, uint256 amount_) external override {
        require(_isPoolDelegate(msg.sender), "DL:PF:NOT_PD");
        Liquidator(liquidator).pullFunds(token_, destination_, amount_);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getExpectedAmount(uint256 swapAmount_) external view override returns (uint256 returnAmount_) {
        address collateralAsset = IMapleLoanLike(loan).collateralAsset();
        address fundsAsset      = IMapleLoanLike(loan).fundsAsset();

        uint256 oracleAmount = 
            swapAmount_
                * IMapleGlobalsLike(_globals()).getLatestPrice(collateralAsset)  // Convert from `fromAsset` value.
                * 10 ** IERC20Like(fundsAsset).decimals()                        // Convert to `toAsset` decimal precision.
                * (10_000 - allowedSlippage)                                     // Multiply by allowed slippage basis points
                / IMapleGlobalsLike(_globals()).getLatestPrice(fundsAsset)       // Convert to `toAsset` value.
                / 10 ** IERC20Like(collateralAsset).decimals()                   // Convert from `fromAsset` decimal precision.
                / 10_000;                                                        // Divide basis points for slippage
        
        uint256 minRatioAmount = swapAmount_ * minRatio / 10 ** IERC20Like(collateralAsset).decimals();

        return oracleAmount > minRatioAmount ? oracleAmount : minRatioAmount;
    }

    function investorFee() external view override returns (uint256 investorFee_) {
        return IPoolLike(pool).investorFee();
    }

    function mapleTreasury() external view override returns (address mapleTreasury_) {
        return IPoolLike(pool).mapleTreasury();
    }

    function poolDelegate() external override view returns(address) {
        return _poolDelegate();
    }

    function treasuryFee() external view override returns (uint256 treasuryFee_) {
        return IPoolLike(pool).treasuryFee();
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _globals() internal view returns (address) {
        return IPoolFactoryLike(IPoolLike(pool).superFactory()).globals();
    }

    function _poolDelegate() internal view returns(address) {
        return IPoolLike(pool).poolDelegate();
    }

    function _isPool(address account_) internal view returns (bool) {
        return account_ == pool;
    }

    function _isPoolDelegate(address account_) internal view returns (bool) {
        return account_ == _poolDelegate();
    }

}
