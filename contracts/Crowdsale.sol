pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "zeppelin-solidity/contracts/ownership/Ownable.sol";
import "zeppelin-solidity/contracts/ownership/CanReclaimToken.sol";
import "zeppelin-solidity/contracts/lifecycle/Destructible.sol";
import "./Token.sol";

contract Crowdsale is Ownable, CanReclaimToken, Destructible {
    using SafeMath for uint256;

    uint64 public startTimestamp;   //Crowdsale start timestamp
    uint64 public endTimestamp;     //Crowdsale end timestamp
    uint256 public goal;            //minimal amount of sold tokens (if not reached - ETH may be refunded)
    uint256 public hardCap;         //total amount of tokens available
    uint256 public rate;            //how many tokens will be minted for 1 ETH
    bool prizeFundSet = false;

    uint256 public tokensSold;      //total amount of tokens sold(!) on ICO
    uint256 public tokensMinted;    //total amount of minted tokens (this includes founder tokens and sold tokens)
    uint256 public collectedEther;  //total amount of ether collected during ICO

    mapping(address => uint256) contributions; //amount of ether (in wei)received from a buyer

    Token public token;

    bool public finalized;

    function Crowdsale(
        uint64 _startTimestamp, uint64 _endTimestamp, uint256 _rate,
        uint256 _founderTokens, uint256 _goal, uint256 _hardCap
        ) public {
        require(_startTimestamp > now);
        require(_startTimestamp < _endTimestamp);
        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;

        require(_hardCap > 0);
        hardCap = _hardCap;

        goal = _goal;

        require(_rate > 0);
        rate = _rate;

        token = new Token();
        token.init(owner);

        require(_founderTokens < _hardCap);
        mintTokens(owner, _founderTokens);
    }

    /**
    * @notice Sell tokens directly, without referral bonuses
    */
    function () public payable {
        require(crowdsaleOpen());
        require(msg.value > 0);
        collectedEther = collectedEther.add(msg.value);
        contributions[msg.sender] = contributions[msg.sender].add(msg.value);
        uint256 amount = getTokensForValue(msg.value);
        tokensSold = tokensSold.add(amount);
        mintTokens(msg.sender, amount);
    }

    /**
    * @notice How many tokens one will receive for specified value of Ether
    * @param value paid
    * @return amount of tokens
    */
    function getTokensForValue(uint256 value) public view returns(uint256) {
        return value.mul(rate);
    }


    /**
    * @notice If crowdsale is running
    */
    function crowdsaleOpen() view public returns(bool) {
        return !finalized && (tokensMinted < hardCap) && (startTimestamp <= now) && (now <= endTimestamp);
    }

    /**
    * @notice Calculates how many tokens are left to sale
    * @return amount of tokens left before hard cap reached
    */
    function getTokensLeft() view public returns(uint256) {
        return hardCap.sub(tokensMinted);
    }

    /**
    * @dev Helper function to mint tokens and increase tokensMinted counter
    */
    function mintTokens(address beneficiary, uint256 amount) internal {
        tokensMinted = tokensMinted.add(amount);
        require(tokensMinted <= hardCap);
        assert(token.mint(beneficiary, amount));
    }

    /**
    * @notice Sends all contributed ether back if minimum cap is not reached by the end of crowdsale
    */
    function refund() public returns(bool){
        return refundTo(msg.sender);
    }
    function refundTo(address beneficiary) public returns(bool) {
        require(contributions[beneficiary] > 0);
        require(finalized || (now > endTimestamp));
        require(tokensSold < goal);

        uint256 value = contributions[beneficiary];
        contributions[beneficiary] = 0;
        beneficiary.transfer(value);
        return true;
    }

    /**
    * @notice Closes crowdsale, finishes minting (allowing token transfers), transfers token ownership to the owner
    */
    function finalizeCrowdsale() public onlyOwner {
        finalized = true;
        token.finishMinting();
        token.transferOwnership(owner);
        if(tokensSold >= goal && this.balance > 0){
            owner.transfer(this.balance);
        }
    }

    /**
    * @notice Claim collected ether without closing crowdsale
    */
    function claimEther() public onlyOwner {
        require(tokensSold >= goal);
        if(this.balance > 0){
            owner.transfer(this.balance);
        }
    }

}

