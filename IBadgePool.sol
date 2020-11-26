pragma solidity 0.6.2;


interface IBadgePool {
    function getYieldAddition(address _addr, uint256 _amount) external view returns (uint256);

    function migrate(IBadgePool _newBadgePoolAddr) external;
}
