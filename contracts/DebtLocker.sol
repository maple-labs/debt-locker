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

    uint256 public override principalRemainingAtLastClaim;

    modifier isPool() {
        require(msg.sender == address(pool), "INVALID_POOL");
        _;
    }

    constructor(address loan_, address pool_) {
        factory                       = msg.sender;
        loan                          = loan_;
        pool                          = pool_;
        principalRemainingAtLastClaim = IMapleLoanLike(loan_).principalRequested();
    }

    function claim() external override isPool returns (uint256[7] memory details_) {
        // Get loan state variables we need
        uint256 claimableFunds = IMapleLoanLike(loan).claimableFunds();
        require(claimableFunds > uint256(0), "DL:C:NOTHING_TO_CLAIM");

        uint256 currentPrincipalRemaining = IMapleLoanLike(loan).principal();

        // Determine how much of claimableFunds are principal and fees
        uint256 principalPortion = principalRemainingAtLastClaim - currentPrincipalRemaining;

        // Send funds to pool and treasury
        IMapleLoanLike(loan).claimFunds(claimableFunds, pool);

        // Update state variables
        principalRemainingAtLastClaim = currentPrincipalRemaining;

        // Set return vales
        details_[0] = claimableFunds;
        details_[1] = uint256(0);
        details_[2] = principalPortion;
        details_[3] = uint256(0);
    }

    function poolDelegate() external override view returns(address) {
        return IPoolLike(pool).poolDelegate();
    }

}
