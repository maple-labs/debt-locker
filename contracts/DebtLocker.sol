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

    function claim() external override isPool returns (uint256[7] memory) {

        uint256 newDefaultSuffered   = uint256(0);
        uint256 loan_defaultSuffered = ILoanLike(loan).defaultSuffered();

        // If a default has occurred, update storage variable and update memory variable from zero for return.
        // `newDefaultSuffered` represents the proportional loss that the DebtLocker registers based on its balance
        // of LoanFDTs in comparison to the total supply of LoanFDTs.
        // Default will occur only once, so below statement will only be `true` once.
        if (lastDefaultSuffered == uint256(0) && loan_defaultSuffered > uint256(0)) {
            newDefaultSuffered = lastDefaultSuffered = _calcAllotment(ILoanLike(loan).balanceOf(address(this)), loan_defaultSuffered, ILoanLike(loan).totalSupply());
        }

        // Account for any transfers into Loan that have occurred since last call.
        ILoanLike(loan).updateFundsReceived();

        // Handles case where no claimable funds are present but a default must be registered (zero-collateralized loans defaulting).
        if (ILoanLike(loan).withdrawableFundsOf(address(this)) == uint256(0)) return([0, 0, 0, 0, 0, 0, newDefaultSuffered]);

        // If there are claimable funds, calculate portions and claim using LoanFDT.

        // Calculate payment deltas.
        uint256 newInterest  = ILoanLike(loan).interestPaid() - lastInterestPaid;    // `loan.interestPaid`  updated in `loan._makePayment()`
        uint256 newPrincipal = ILoanLike(loan).principalPaid() - lastPrincipalPaid;  // `loan.principalPaid` updated in `loan._makePayment()`

        // Update storage variables for next delta calculation.
        lastInterestPaid  = ILoanLike(loan).interestPaid();
        lastPrincipalPaid = ILoanLike(loan).principalPaid();

        // Calculate one-time deltas if storage variables have not yet been updated.
        uint256 newFee             = lastFeePaid         == uint256(0) ? ILoanLike(loan).feePaid()         : uint256(0);  // `loan.feePaid`          updated in `loan.drawdown()`
        uint256 newExcess          = lastExcessReturned  == uint256(0) ? ILoanLike(loan).excessReturned()  : uint256(0);  // `loan.excessReturned`   updated in `loan.unwind()` OR `loan.drawdown()` if `amt < fundingLockerBal`
        uint256 newAmountRecovered = lastAmountRecovered == uint256(0) ? ILoanLike(loan).amountRecovered() : uint256(0);  // `loan.amountRecovered`  updated in `loan.triggerDefault()`

        // Update DebtLocker storage variables if Loan storage variables has been updated since last claim.
        if (newFee > 0)             lastFeePaid         = newFee;
        if (newExcess > 0)          lastExcessReturned  = newExcess;
        if (newAmountRecovered > 0) lastAmountRecovered = newAmountRecovered;

        // Withdraw all claimable funds via LoanFDT.
        uint256 beforeBal = IERC20(liquidityAsset).balanceOf(address(this));                 // Current balance of DebtLocker (accounts for direct inflows).
        ILoanLike(loan).withdrawFunds();                                                     // Transfer funds from Loan to DebtLocker.
        uint256 claimBal  = IERC20(liquidityAsset).balanceOf(address(this)).sub(beforeBal);  // Amount claimed from Loan using LoanFDT.

        // Calculate sum of all deltas, to be used to calculate portions for metadata.
        uint256 sum = newInterest.add(newPrincipal).add(newFee).add(newExcess).add(newAmountRecovered);

        // Calculate payment portions based on LoanFDT claim.
        newInterest  = _calcAllotment(newInterest,  claimBal, sum);
        newPrincipal = _calcAllotment(newPrincipal, claimBal, sum);

        // Calculate one-time portions based on LoanFDT claim.
        newFee             = _calcAllotment(newFee,             claimBal, sum);
        newExcess          = _calcAllotment(newExcess,          claimBal, sum);
        newAmountRecovered = _calcAllotment(newAmountRecovered, claimBal, sum);

        IERC20(liquidityAsset).safeTransfer(pool, claimBal);  // Transfer entire amount claimed using LoanFDT.

        // Return claim amount plus all relevant metadata, to be used by Pool for further claim logic.
        // Note: newInterest + newPrincipal + newFee + newExcess + newAmountRecovered = claimBal - dust
        //       The dust on the right side of the equation gathers in the pool after transfers are made.
        return([claimBal, newInterest, newPrincipal, newFee, newExcess, newAmountRecovered, newDefaultSuffered]);
    }

    function triggerDefault() external override isPool {
        ILoanLike(loan).triggerDefault();
    }

}
