// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { ERC20Helper, IERC20 } from "../modules/erc20-helper/src/ERC20Helper.sol";

import { IDebtLocker }        from "./interfaces/IDebtLocker.sol";
import { IDebtLockerFactory } from "./interfaces/IDebtLockerFactory.sol";

import { IMapleGlobalsLike, IMapleLoanLike, IPoolLike, IUniswapRouterLike }  from "./interfaces/Interfaces.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLocker is IDebtLocker {

    address internal constant UNISWAP_ROUTER = address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public override immutable factory;
    address public override immutable loan;
    address public override immutable pool;

    bool public override hasMadeFirstClaim;

    uint256 public override principalRemainingAtLastClaim;

    constructor(address loan_, address pool_) {
        factory                       = msg.sender;
        loan                          = loan_;
        pool                          = pool_;
        hasMadeFirstClaim             = false;
        principalRemainingAtLastClaim = IMapleLoanLike(loan_).principalRequested();
    }

    function claim() external override returns (uint256[7] memory details_) {
        if (IMapleLoanLike(loan).lender() == address(0)) return _handleDefaultClaim();

        // Get loan state variables we need
        uint256 claimableFunds = IMapleLoanLike(loan).claimableFunds();
        require(claimableFunds > uint256(0), "DL:C:NOTHING_TO_CLAIM");

        uint256 currentPrincipalRemaining = IMapleLoanLike(loan).principal();

        // Get Globals variables
        address globals         = IDebtLockerFactory(factory).globals();
        uint256 investorFeeRate = IMapleGlobalsLike(globals).investorFee();

        // Determine how much of claimableFunds are principal and fees
        uint256 principalPortion = principalRemainingAtLastClaim - currentPrincipalRemaining;
        uint256 feePortion       = claimableFunds - principalPortion;

        // Determine the the split of fees between the treasury, pool delegate, and pool
        uint256 poolDelegateFees;
        uint256 treasuryFees;

        // Determine if this claim includes proceeds from initial funding
        if (!hasMadeFirstClaim) {
            hasMadeFirstClaim = true;
            poolDelegateFees  = (principalRemainingAtLastClaim * investorFeeRate) / uint256(10_000);
            treasuryFees      = (principalRemainingAtLastClaim * IMapleGlobalsLike(globals).treasuryFee()) / uint256(10_000);
        }

        // Determine the the split of fees
        poolDelegateFees += (feePortion * investorFeeRate) / uint256(10_000);

        uint256 poolFees = feePortion - poolDelegateFees - treasuryFees;

        // Send funds to pool and treasury
        if (poolFees > uint256(0)) {
            IMapleLoanLike(loan).claimFunds(claimableFunds - treasuryFees, pool);
        }

        if (treasuryFees > uint256(0)) {
            IMapleLoanLike(loan).claimFunds(treasuryFees, IMapleGlobalsLike(globals).mapleTreasury());
        }

        // Update state variables
        principalRemainingAtLastClaim = currentPrincipalRemaining;

        // Set return vales
        details_[0] = claimableFunds - treasuryFees;
        details_[1] = poolFees;
        details_[2] = principalPortion;
        details_[3] = poolDelegateFees;
    }

    function triggerDefault() external override {
        require(msg.sender == pool, "DL:TD:NOT_POOL");

        ( uint256 collateralAssetAmount_, ) = IMapleLoanLike(loan).repossess(address(this), address(this));

        _swap(
            collateralAssetAmount_,
            IMapleLoanLike(loan).collateralAsset(),
            IMapleLoanLike(loan).fundsAsset(),
            address(this)
        );
    }

    function _swap(uint256 fromAmount_, address fromAsset_, address toAsset_, address destination) internal returns (uint256 toAmount_) {
        if (fromAsset_ == toAsset_ || fromAmount_ == uint256(0)) return uint256(0);

        require(ERC20Helper.approve(fromAsset_, UNISWAP_ROUTER, fromAmount_), "DL:LC:FAILED_TO_SWAP");

        // Generate Uniswap path.
        address intermediateAsset = IMapleGlobalsLike(IDebtLockerFactory(factory).globals()).defaultUniswapPath(fromAsset_, toAsset_);

        bool middleAsset = intermediateAsset != toAsset_ && intermediateAsset != address(0);

        address[] memory path = new address[](middleAsset ? 3 : 2);

        path[0] = fromAsset_;
        path[1] = middleAsset ? intermediateAsset : toAsset_;

        if (middleAsset) {
            path[2] = toAsset_;
        }

        // Swap fromAsset_ for Liquidity Asset.
        return IUniswapRouterLike(UNISWAP_ROUTER).swapExactTokensForTokens(fromAmount_, 0, path, destination, block.timestamp)[path.length - 1];
    }

    function _handleDefaultClaim() internal returns (uint256[7] memory details_) {
        address fundsAsset     = IMapleLoanLike(loan).fundsAsset();
        uint256 recoveredFunds = IERC20(fundsAsset).balanceOf(address(this));

        ERC20Helper.transfer(fundsAsset, pool, recoveredFunds);

        // Either all of principalRemainingAtLastClaim was recovered, or just recoveredFunds amount of it
        uint256 recoveredPrincipal = recoveredFunds >= principalRemainingAtLastClaim
            ? principalRemainingAtLastClaim
            : recoveredFunds;
        
        uint256 recoveredFees;
        uint256 poolDelegateFees;

        if (recoveredFunds > principalRemainingAtLastClaim) {
            recoveredFees    = recoveredFunds - principalRemainingAtLastClaim;
            poolDelegateFees = (recoveredFees * IMapleGlobalsLike(IDebtLockerFactory(factory).globals()).investorFee()) / uint256(10_000);
        } 

        // Set return vales
        details_[0] = recoveredFunds;
        details_[1] = recoveredFees - poolDelegateFees;
        details_[2] = recoveredPrincipal;
        details_[3] = poolDelegateFees;
        details_[5] = 0;
        details_[6] = principalRemainingAtLastClaim - recoveredPrincipal;

        // Update state variables
        principalRemainingAtLastClaim = 0;
    }
}
