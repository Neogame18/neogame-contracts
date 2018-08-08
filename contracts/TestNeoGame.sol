pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "./NeoGame.sol";


contract TestNeoGame is NeoGame, Ownable {

    constructor(address _token) NeoGame(_token) public {}

    function getBigWinnersLength(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].bigPrizeWinners.length;
    }

    // ---- ONLY FOR TESTING PURPOSES. REMOVE BEFORE PRODUCTION DEPLOY
    function __setBlockNumber(uint256 _gameIndex, uint256 _blockNumber) public onlyOwner returns(uint256) {
        games[_gameIndex].block = _blockNumber;
        return games[_gameIndex].block;
    }

    // ---- ONLY FOR TESTING PURPOSES. REMOVE BEFORE PRODUCTION DEPLOY
    function __setWinnerNumbers(uint256 _gameIndex, uint8[BET_SIZE] _winningNumbers, uint8 _bonusNumber) onlyOwner {
        games[_gameIndex].winningNumbers = _winningNumbers;
        games[_gameIndex].bonusNumber = _bonusNumber;
        if (games[_gameIndex].prizeFund == 0) {
            games[_gameIndex].prizeFund = calculatePrizeFund();
        }
        setNewReferenceGameToExpiredGames(_gameIndex);
        emit WinnerNumbersBeingSet(_gameIndex);
    }
}