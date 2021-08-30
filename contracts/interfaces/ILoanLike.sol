// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.11;

import { IERC20 } from "../../modules/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface ILoanLike is IERC20 {

    function amountRecovered() external view returns (uint256);

    function defaultSuffered() external view returns (uint256);

    function excessReturned() external view returns (uint256);

    function feePaid() external view returns (uint256);

    function interestPaid() external view returns (uint256);

    function liquidityAsset() external view returns (address);

    function principalPaid() external view returns (uint256);

    function updateFundsReceived() external;

    function withdrawableFundsOf(address) external view returns (uint256);

    function withdrawFunds() external;

    function triggerDefault() external;

}
