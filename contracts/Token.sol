pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/ownership/NoOwner.sol';

contract Token is MintableToken, NoOwner {
    string public symbol = 'TKT';
    string public name = 'Ticket token';
    uint8 public constant decimals = 18;

    address founder; //founder address to allow him transfer tokens while minting
    function init(address _founder) onlyOwner public {
        founder = _founder;
    }

    function getFounder() public returns(address) {
        return founder;
    }

    /**
     * Allow transfer only after crowdsale finished
     */
    modifier canTransfer() {
        require(mintingFinished || msg.sender == founder);
        _;
    }

    function transfer(address _to, uint256 _value) canTransfer public returns (bool) {
        return super.transfer(_to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) canTransfer public returns (bool) {
        return super.transferFrom(_from, _to, _value);
    }
}

