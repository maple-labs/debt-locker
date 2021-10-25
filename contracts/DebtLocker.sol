// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IMapleProxyFactory } from "../modules/maple-proxy-factory/contracts/interfaces/IMapleProxyFactory.sol";

import { ERC20Helper }  from "../modules/erc20-helper/src/ERC20Helper.sol";
import { Liquidator }   from "../modules/liquidations/contracts/Liquidator.sol";
import { MapleProxied } from "../modules/maple-proxy-factory/contracts/MapleProxied.sol";

import { IDebtLocker }                                                                from "./interfaces/IDebtLocker.sol";
import { IERC20Like, IMapleGlobalsLike, IMapleLoanLike, IPoolLike, IPoolFactoryLike } from "./interfaces/Interfaces.sol";

import { DebtLockerStorage } from "./DebtLockerStorage.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLocker is IDebtLocker, DebtLockerStorage, MapleProxied {

    /********************************/
    /*** Administrative Functions ***/
    /********************************/

    function migrate(address migrator_, bytes calldata arguments_) external override {
        require(msg.sender == _factory(),        "DL:M:NOT_FACTORY");
        require(_migrate(migrator_, arguments_), "DL:M:FAILED");
    }

    function setImplementation(address newImplementation_) external override {
        require(msg.sender == _factory(),               "DL:SI:NOT_FACTORY");
        require(_setImplementation(newImplementation_), "DL:SI:FAILED");
    }

    function upgrade(uint256 toVersion_, bytes calldata arguments_) external override {
        require(msg.sender == IPoolLike(_pool).poolDelegate(), "DL:U:NOT_POOL_DELEGATE");

        IMapleProxyFactory(_factory()).upgradeInstance(toVersion_, arguments_);
    }

    /*******************************/
    /*** Pool Delegate Functions ***/
    /*******************************/

    function claim() external override returns (uint256[7] memory details_) {
        require(msg.sender == _pool, "DL:C:NOT_POOL");

        return _repossessed ? _handleClaimOfRepossessed() : _handleClaim();
    }

    function setAllowedSlippage(uint256 allowedSlippage_) external override {
        require(msg.sender == _getPoolDelegate(), "DL:SAS:NOT_PD");

        _allowedSlippage = allowedSlippage_;
    }

    function setAuctioneer(address auctioneer_) external override {
        require(msg.sender == _getPoolDelegate(), "DL:SA:NOT_PD");

        Liquidator(_liquidator).setAuctioneer(auctioneer_);
    }

    function setMinRatio(uint256 minRatio_) external override {
        require(msg.sender == _getPoolDelegate(), "DL:SA:NOT_PD");

        _minRatio = minRatio_;
    }

    function triggerDefault() external override {
        require(msg.sender == _pool, "DL:TD:NOT_POOL");
        require(
            IMapleLoanLike(_loan).claimableFunds() == 0 &&
            IMapleLoanLike(_loan).principal() == _principalRemainingAtLastClaim,
            "DL:TD:NEED_TO_CLAIM"
        );

        _repossessed = true;

        // Ensure that principal is always up to date, claim function will clear out all payments, but on refinance we need to ensure that
        // accounting is updated properly when principal is updated and there are no claimable funds.

        // Repossess collateral and funds from Loan.
        ( uint256 collateralAssetAmount, ) = IMapleLoanLike(_loan).repossess(address(this), address(this));

        address collateralAsset = IMapleLoanLike(_loan).collateralAsset();
        address fundsAsset      = IMapleLoanLike(_loan).fundsAsset();

        if (collateralAsset == fundsAsset || collateralAssetAmount == 0) return;

        // Deploy Liquidator contract and transfer collateral.
        require(
            ERC20Helper.transfer(
                collateralAsset,
                _liquidator = address(new Liquidator(address(this), collateralAsset, fundsAsset, address(this), address(this))),
                collateralAssetAmount
            ),
            "DL:TD:TRANSFER"
       );
    }

    // TODO: Add setters for allowed slippage and minRatio

    /**********************/
    /*** View Functions ***/
    /**********************/

    function allowedSlippage() external view override returns (uint256 allowedSlippage_) {
        return _allowedSlippage;
    }

    function amountRecovered() external view override returns (uint256 amountRecovered_) {
        return _amountRecovered;
    }

    function factory() external view override returns (address) {
        return _factory();
    }

    function getExpectedAmount(uint256 swapAmount_) external view override returns (uint256 returnAmount_) {
        address collateralAsset = IMapleLoanLike(_loan).collateralAsset();
        address fundsAsset      = IMapleLoanLike(_loan).fundsAsset();

        uint256 oracleAmount =
            swapAmount_
                * IMapleGlobalsLike(_getGlobals()).getLatestPrice(collateralAsset)  // Convert from `fromAsset` value.
                * 10 ** IERC20Like(fundsAsset).decimals()                           // Convert to `toAsset` decimal precision.
                * (10_000 - _allowedSlippage)                                       // Multiply by allowed slippage basis points
                / IMapleGlobalsLike(_getGlobals()).getLatestPrice(fundsAsset)       // Convert to `toAsset` value.
                / 10 ** IERC20Like(collateralAsset).decimals()                      // Convert from `fromAsset` decimal precision.
                / 10_000;                                                           // Divide basis points for slippage

        uint256 minRatioAmount = swapAmount_ * _minRatio / 10 ** IERC20Like(collateralAsset).decimals();

        return oracleAmount > minRatioAmount ? oracleAmount : minRatioAmount;
    }

    function implementation() external view override returns (address) {
        return _implementation();
    }

    function investorFee() external view override returns (uint256 investorFee_) {
        return IPoolLike(_pool).investorFee();
    }

    function liquidator() external view override returns (address liquidator_) {
        return _liquidator;
    }

    function loan() external view override returns (address loan_) {
        return _loan;
    }

    function mapleTreasury() external view override returns (address mapleTreasury_) {
        return IPoolLike(_pool).mapleTreasury();
    }

    function minRatio() external view override returns (uint256 minRatio_) {
        return _minRatio;
    }

    function pool() external view override returns (address pool_) {
        return _pool;
    }

    function poolDelegate() external override view returns(address) {
        return _getPoolDelegate();
    }

    function principalRemainingAtLastClaim() external view override returns (uint256 principalRemainingAtLastClaim_) {
        return _principalRemainingAtLastClaim;
    }

    function repossessed() external view override returns (bool repossessed_) {
        return _repossessed;
    }

    function treasuryFee() external view override returns (uint256 treasuryFee_) {
        return IPoolLike(_pool).treasuryFee();
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _handleClaimOfRepossessed() internal returns (uint256[7] memory details_) {
        require(!_isLiquidationActive(), "DL:C:LIQ_NOT_FINISHED");

        address fundsAsset       = IMapleLoanLike(_loan).fundsAsset();
        uint256 recoveredFunds   = IERC20Like(fundsAsset).balanceOf(address(this));  // Funds recovered from liquidation and any unclaimed previous payment amounts
        uint256 principalToCover = _principalRemainingAtLastClaim;                   // Principal remaining at time of liquidation

        // If `recoveredFunds` is greater than `principalToCover`, the remaining amount is treated as interest in the context of the pool.
        // If `recoveredFunds` is less than `principalToCover`, the difference is registered as a shortfall.
        details_[0] = recoveredFunds;
        details_[1] = recoveredFunds > principalToCover ? recoveredFunds - principalToCover : 0;
        details_[2] = recoveredFunds > principalToCover ? principalToCover : recoveredFunds;
        details_[5] = recoveredFunds;
        details_[6] = principalToCover > recoveredFunds ? principalToCover - recoveredFunds : 0;

        require(ERC20Helper.transfer(fundsAsset, _pool, recoveredFunds), "DL:C:TRANSFER");

        _repossessed = false;

        // TODO: Consider loan principal after liquidation, if this is called again after being set to zero it would overflow.
    }

    function _handleClaim() internal returns (uint256[7] memory details_) {
        // Get loan state variables needed
        uint256 claimableFunds = IMapleLoanLike(_loan).claimableFunds();

        require(claimableFunds > uint256(0), "DL:C:NOTHING_TO_CLAIM");

        // Send funds to pool
        IMapleLoanLike(_loan).claimFunds(claimableFunds, _pool);

        uint256 currentPrincipalRemaining = IMapleLoanLike(_loan).principal();

        // Determine how much of `claimableFunds` is principal
        uint256 principalPortion = _principalRemainingAtLastClaim - currentPrincipalRemaining;

        // Update state variables
        _principalRemainingAtLastClaim = currentPrincipalRemaining;

        // Set return values
        // Note - All fees get deducted and transferred during `loan.fundLoan()` that omits the need to
        // return the fees distribution to the pool.
        details_[0] = claimableFunds;
        details_[1] = claimableFunds - principalPortion;
        details_[2] = principalPortion;
    }

    /*******************************/
    /*** Internal View Functions ***/
    /*******************************/

    function _getGlobals() internal view returns (address) {
        return IPoolFactoryLike(IPoolLike(_pool).superFactory()).globals();
    }

    function _getPoolDelegate() internal view returns(address) {
        return IPoolLike(_pool).poolDelegate();
    }

    function _isLiquidationActive() internal view returns (bool) {
        return _liquidator != address(0) && IERC20Like(IMapleLoanLike(_loan).collateralAsset()).balanceOf(_liquidator) > 0;
    }

}
