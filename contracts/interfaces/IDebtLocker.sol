// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title DebtLocker holds custody of LoanFDT tokens.
interface IDebtLocker {

    function factory() external view returns (address factory_);

    /**
        @dev The Loan contract this locker is holding tokens for.
     */
    function loan() external view returns (address loan_);

    /**
        @dev The owner of this Locker (the Pool).
     */
    function pool() external view returns (address pool_);

    function hasMadeFirstClaim() external view returns (bool hasMadeFirstClaim_);

    function principalRemainingAtLastClaim() external view returns (uint256 principalRemainingAtLastClaim_);

    /**
        @dev    Claims funds distribution for Loan via LoanFDT.
        @dev    Only the Pool can call this function.
        @return details_
                    [0] => Total Claimed.
                    [1] => Fees Claimed.
                    [2] => Principal Claimed.
                    [3] => Pool Delegate Fees Claimed.
                    [4] => Excess Returned Claimed.
                    [5] => Amount Recovered (from Liquidation).
                    [6] => Default Suffered.
     */
    function claim() external returns (uint256[7] memory details_);

    /**
        @dev Liquidates a Loan that is held by this contract.
        @dev Only the Pool can call this function.
     */
    function triggerDefault() external;

}
