// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IMapleProxied } from "../../modules/maple-proxy-factory/contracts/interfaces/IMapleProxied.sol";

import "./IDebtLockerStorage.sol";


/// @title DebtLocker holds custody of LoanFDT tokens.
interface IDebtLocker is IDebtLockerStorage, IMapleProxied {

    /**
        @dev    Claims funds to send to Pool. Handles funds from payments and liquidations.
        @dev    Only the Pool can call this function.
        @return details_
                    [0] => Total Claimed.
                    [1] => Interest Claimed.
                    [2] => Principal Claimed.
                    [3] => Pool Delegate Fees Claimed.
                    [4] => Excess Returned Claimed.
                    [5] => Amount Recovered (from Liquidation).
                    [6] => Default Suffered.
     */
    function claim() external returns (uint256[7] memory details_);

    /**
     * @dev Returns the annualized establishment fee that will go to the PoolDelegate.
     */
    function investorFee() external view returns (uint256 investorFee_);

    /**
     * @dev Returns the addres of the Maple Treasury.
     */
    function mapleTreasury() external view returns (address mapleTreasury_);

    /**
     * @dev Returns the annualized estabishment fee that will go to the Maple Treasury.
     */
    function treasuryFee() external view returns (uint256 treasuryFee_);

    /**
     * @dev Returns the address of the Pool Delegate that has control of the DebtLocker.
     */
    function poolDelegate() external view returns (address poolDelegate_);

    /**
     * @dev Repossesses funds and collateral from a loan and transfers them to the Liquidator.
     */
    function triggerDefault() external;

    /**
     * @dev Sets the auctioneer contract for the liquidator.
     * @param auctioneer_ Address of auctioneer contract.
     */
    function setAuctioneer(address auctioneer_) external;

    /**
     * @dev Returns the expected amount to be returned to the liquidator during a flash borrower liquidation.
     * @param swapAmount_    Amount of collateralAsset being swapped.
     * @return returnAmount_ Amount of fundsAsset that must be returned in the same transaction.
     */
    function getExpectedAmount(uint256 swapAmount_) external view returns (uint256 returnAmount_);

}
