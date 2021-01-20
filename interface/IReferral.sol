// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IReferral is IERC20 {
    function getReferrals(address _addr) external view returns (address[] memory);

    function getInvitees(address _addr) external view returns (address[] memory);
}
