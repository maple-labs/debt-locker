// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { SafeMath }          from "../modules/openzeppelin-contracts/contracts/math/SafeMath.sol";
import { IERC20, SafeERC20 } from "../modules/openzeppelin-contracts/contracts/token/ERC20/SafeERC20.sol";

import { IDebtLocker } from "./interfaces/IDebtLocker.sol";
import { ILoanLike }   from "./interfaces/ILoanLike.sol";

/// @title DebtLocker holds custody of LoanFDT tokens.
contract DebtLocker is IDebtLocker {

    using SafeMath  for uint256;
    using SafeERC20 for IERC20;

    uint256 constant WAD = 10 ** 18;

    address public override immutable loan;
    address public override immutable liquidityAsset;
    address public override immutable pool;

    uint256 public override lastPrincipalPaid;
    uint256 public override lastInterestPaid;
    uint256 public override lastFeePaid;
    uint256 public override lastExcessReturned;
    uint256 public override lastDefaultSuffered;
    uint256 public override lastAmountRecovered;

    uint256 public override lastClaimableFunds;
    uint256 public override lastClaimDate;

    /**
        @dev Checks that `msg.sender` is the Pool.
     */
    modifier isPool() {
        require(msg.sender == pool, "DL:NOT_P");
        _;
    }

    constructor(address _loan, address _pool) public {
        loan           = _loan;
        pool           = _pool;
        liquidityAsset = ILoanLike(_loan).liquidityAsset();
    }

    // Note: If newAmt > 0, totalNewAmt will always be greater than zero.
    function _calcAllotment(uint256 newAmt, uint256 totalClaim, uint256 totalNewAmt) internal pure returns (uint256) {
        return newAmt == uint256(0) ? uint256(0) : newAmt.mul(totalClaim).div(totalNewAmt);
    }

    // TODO: Need to take care the liquidations part here.
    // TODO: Need to add the process where pool can claim the excess amount of fundsAsset from the debt locker contract.
    function claim() external override isPool returns (uint256[7] memory) {
        (uint256 totalPrincipalAmount_, uint256 totalInterestFees_, uint256 totalLateFees_) = ILoanLike(loan).getPaymentsBreakdownForClaim(lastClaimDate);
        uint256 totalClaimableFunds = totalPrincipalAmount_ + totalInterestFees_ + totalLateFees_;
        
        // Claim funds from the loan contract.
        if (totalClaimableFunds > uint256(0) && totalClaimableFunds - lastClaimableFunds > uint256(0)) {
            lastClaimableFunds += totalClaimableFunds;
            ILoanLike(loan).claimFunds(totalClaimableFunds, msg.sender);
            return [totalClaimableFunds, totalInterestFees_, totalPrincipalAmount_, totalLateFees_, uint256(0), uint256(0), uint256(0)];
        }
        return [uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0), uint256(0)];
    }

    function triggerDefault() external override isPool {
        ILoanLike(loan).triggerDefault();
    }

}
