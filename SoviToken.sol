// SPDX-License-Identifier: MIT
pragma solidity 0.6.8;


import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SoviToken is ERC20("Sovi Token", "SOVI"), Ownable {

    // for minters
    mapping(address => bool) public _minters;

    // @dev Initialize the Token
    constructor () public {
    }

    // @notice Creates `_amount` token to `_to`. Must only be called by the minter.
    function mint(address _to, uint256 _amount) public {
        require(_minters[msg.sender], "!minter");

        _mint(_to, _amount);
    }

    function addMinter(address _minter) public onlyOwner {
        _minters[_minter] = true;
    }

    function removeMinter(address _minter) public onlyOwner {
        _minters[_minter] = false;
    }
}
