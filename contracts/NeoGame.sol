pragma solidity ^0.4.19;

import "zeppelin-solidity/contracts/token/ERC20/SafeERC20.sol";
import "./Token.sol";

contract NeoGame {
    uint8 constant internal BET_SIZE = 5;
    uint8 constant internal TECH_BONUS = 10;
    uint8 constant internal SECONDS_PER_BLOCK = 15;
    uint8 constant internal FAST_WITHDRAW_PERCENTAGE_LIMIT = 20;
    uint8 constant internal BONUS_BET_VARIANTS = 21;
    uint8 constant internal MAIN_BET_VARIANTS = 49;
    uint8 constant internal PRIZE_FUND_PERCENTAGE = 70;
    uint8 constant internal ALL_BETS_ARE_MADE = 240;
    uint16 constant internal BLOCK_QUANTITY_ETHEREUM_IS_SAVING = 256;
    uint16 constant internal BLOCKS_PER_PERIOD = 40320;  // ((86400 / 15) * 7);
    uint32 constant internal PERIOD_IN_SECONDS = 604800;

    using SafeERC20 for Token;

    event NewBet(uint256 gameIndex, uint256 ticketIndex, address player);
    event GameCreated(uint256 gameIndex);
    event WinnerNumbersBeingSet(uint256 gameIndex);
    event PrizeSent(uint256 gameIndex, uint256 ticketIndex, uint256 prize, address player);

    modifier gameIsNotExpired(uint256 _gameIndex) {
        require(!isGameExpired(_gameIndex));
        _;
    }

    modifier gameNumbersNotSet(uint256 _gameIndex) {
        require(!isGameNumbersAreDefined(_gameIndex));
        _;
    }

    modifier blockNumberIsEnoughToDefineWinnerNumbers(uint256 _gameIndex) {
        require(block.number > games[_gameIndex].block + BET_SIZE + 1);
        _;
    }

    modifier gameIsNotReleased(uint256 _gameIndex) {
        require(!isGameReleased(_gameIndex));
        _;
    }

    modifier ticketIsNotReleased(uint256 _gameIndex, uint256 _ticketIndex) {
        require(!games[_gameIndex].tickets[_ticketIndex].released);
        _;
    }

    struct Ticket {
        address player;
        uint8[BET_SIZE] mainBet;
        uint8 bonusBet;
        uint256 amount;
        bool released;
    }

    struct BigPrizeWinner {
        address player;
        uint256 win;
    }

    struct Game {
        uint8[BET_SIZE] winningNumbers;
        uint8 bonusNumber;
        uint256 referenceGame;
        uint256 block;
        uint256 prizeFund;
        bool released;
        Ticket[] tickets;
        BigPrizeWinner[] bigPrizeWinners;
    }

    Token public token;
    Game[] public games;

    function NeoGame(address _token) public {
        token = Token(_token);
    }

    /**
    * 0 Fallback function
    */
    function() public {revert();}

    function getWinningNumbers(uint256 _blockNumber) public view returns (uint8[5], uint8) {
        uint8[5] memory winningNumbers = [0, 0, 0, 0, 0];
        uint8 index = 0;
        uint8 indexOffset = 0;
        uint8 newNumber;
        uint8 bonusNumber;

        while (index < 5 &&
        (block.number >= _blockNumber + indexOffset) &&
        (_blockNumber + BLOCK_QUANTITY_ETHEREUM_IS_SAVING > block.number)) {
            newNumber = getBallNumber(_blockNumber + indexOffset, MAIN_BET_VARIANTS);
            indexOffset++;

            if (!inArray(winningNumbers, newNumber)) {
                winningNumbers[index] = newNumber;
                index++;
            }
        }

        if (index > 4) {
            bonusNumber = getBallNumber(_blockNumber + indexOffset, BONUS_BET_VARIANTS);
        }

        if (bonusNumber == 0) {
            winningNumbers = [0, 0, 0, 0, 0];
        }

        return (winningNumbers, bonusNumber);
    }

    function getBallNumber(uint256 _blockNumber, uint8 _numberVariants) public view returns (uint8) {
        return uint8(uint256(block.blockhash(_blockNumber)) % _numberVariants + 1);
    }

    /**
    * 3.4.1.1 Get matches. How much numbers are the same in 2 arrays
    * 1st array is winner numbers
    * 2nd is the bet (bet is always ascending for optimisation
    */
    function getMatches(uint8[BET_SIZE] _winningNumbers, uint8[BET_SIZE] _bet) public pure returns (uint8) {
        uint8 matches = 0;
        for (uint m = 0; m < BET_SIZE; m++) {
            for (uint j = 0; j < BET_SIZE; j++) {
                if (_winningNumbers[m] == _bet[j]) {
                    matches++;
                    break;
                } else if (_winningNumbers[m] < _bet[j]) {
                    // bet is always ascending
                    break;
                }
            }
        }
        return matches;
    }

    /**
    * 2.1 Calculating the next game block number
    */
    function getNextPeriodBlock() public view returns (uint256) {
        uint256 secondsPassedInCurrentPeriod = now % PERIOD_IN_SECONDS;
        uint256 nextBlock = block.number + ((PERIOD_IN_SECONDS - secondsPassedInCurrentPeriod) / SECONDS_PER_BLOCK);
        if (block.number + ALL_BETS_ARE_MADE > nextBlock) {
            nextBlock = nextBlock + BLOCKS_PER_PERIOD;
        }
        return nextBlock;
    }

    /**
    * 1 Make a bet
    */
    function bet(uint256 _amount, uint8[BET_SIZE] _mainBet, uint8 _bonusBet) public {
        require(_amount > 0);
        requireBetCorrect(_mainBet, _bonusBet);

        if (isNeedToCreateNewGame()) {
            createGame();
        }

        token.safeTransferFrom(msg.sender, address(this), _amount);

        games[games.length - 1].tickets.push(
            Ticket({
                player : msg.sender,
                amount : _amount,
                mainBet : _mainBet,
                bonusBet : _bonusBet,
                released : false
            }));
        NewBet(games.length - 1, games[games.length - 1].tickets.length - 1, msg.sender);
    }

    function createGame() private {
        if (games.length > 0) {
            if (games.length > 1) {
                releaseGame(games.length - 2);
            }
            if (games[games.length - 1].prizeFund == 0) {
                games[games.length - 1].prizeFund = calculatePrizeFund();
            }
        }
        games.length++;
        uint256 gameIndex = games.length - 1;
        games[gameIndex].block = getNextPeriodBlock();
        games[gameIndex].referenceGame = gameIndex;
        GameCreated(games.length - 1);
    }

    function calculatePrizeFund() public view returns (uint256) {
        return token.balanceOf(address(this)) * PRIZE_FUND_PERCENTAGE / 100;
    }

    function isGameNumbersAreDefined(uint256 _gameIndex) public view returns (bool) {
        return (games[_gameIndex].bonusNumber != 0);
    }

    function isGameExpired(uint256 _gameIndex) public view returns (bool) {
        return (block.number >= games[_gameIndex].block + BLOCK_QUANTITY_ETHEREUM_IS_SAVING);
    }

    function isNeedToCreateNewGame() public view returns (bool) {
        if (games.length == 0) {
            return true;
        } else if (block.number + ALL_BETS_ARE_MADE > games[games.length - 1].block) {
            return true;
        }
        return false;
    }

    function isGameReleased(uint256 _gameIndex) public view returns (bool) {
        return games[games[_gameIndex].referenceGame].released;
    }

    function releaseGame(uint256 _gameIndex) private {
        sendJackPots(_gameIndex);
        games[_gameIndex].released = true;
    }

    function sendJackPots(uint256 _gameIndex) private {
        if (isGameReleased(_gameIndex)) {
            return;
        }
        if (!isGameNumbersAreDefined(_gameIndex)) {
            return;
        }

        uint256 allBigWinnersPrizes = calculateBigWinnersPrizes(_gameIndex);
        uint256 bigPrizeWinnersLength = games[_gameIndex].bigPrizeWinners.length;
        uint256 win;
        uint i = 0;
        if (allBigWinnersPrizes <= games[_gameIndex].prizeFund) {
            for (i = 0; i < bigPrizeWinnersLength; i++) {
                if (games[_gameIndex].bigPrizeWinners[i].win == 0) {
                    win = games[_gameIndex].prizeFund;
                } else {
                    win = games[_gameIndex].bigPrizeWinners[i].win;
                }
                token.safeTransfer(games[_gameIndex].bigPrizeWinners[i].player, win);
                PrizeSent(_gameIndex, 0, win, games[_gameIndex].bigPrizeWinners[i].player);
            }

        } else {
            for (i = 0; i < bigPrizeWinnersLength; i++) {
                if (games[_gameIndex].bigPrizeWinners[i].win == 0) {
                    win = games[_gameIndex].prizeFund;
                } else {
                    win = games[_gameIndex].bigPrizeWinners[i].win;
                }
                win = win * games[_gameIndex].prizeFund / allBigWinnersPrizes;
                token.safeTransfer(games[_gameIndex].bigPrizeWinners[i].player, win);
                PrizeSent(_gameIndex, 0, win, games[_gameIndex].bigPrizeWinners[i].player);
            }
        }
        delete games[_gameIndex].bigPrizeWinners;
    }

    function setNewReferenceGameToExpiredGames(uint256 _referenceIndex) private {
        if (_referenceIndex > 0) {
            for (uint256 i = _referenceIndex - 1; i >= 0; i--) {

                if (isGameNumbersAreDefined(i)) {
                    break;
                } else {
                    games[i].referenceGame = _referenceIndex;
                }
            }
        }
    }

    function setWinnerNumbers(uint256 _gameIndex)
    gameNumbersNotSet(_gameIndex)
    blockNumberIsEnoughToDefineWinnerNumbers(_gameIndex)
    gameIsNotExpired(_gameIndex)
    {
        (games[_gameIndex].winningNumbers, games[_gameIndex].bonusNumber) = getWinningNumbers(games[_gameIndex].block);
    if (isGameNumbersAreDefined(_gameIndex)) {
            if (games[_gameIndex].prizeFund == 0) {
                games[_gameIndex].prizeFund = calculatePrizeFund();
            }
            token.safeTransfer(msg.sender, TECH_BONUS);
            setNewReferenceGameToExpiredGames(_gameIndex);
            WinnerNumbersBeingSet(_gameIndex);
        }
    }

    function calculateBigWinnersPrizes(uint256 _gameIndex) public view returns (uint256) {
        uint256 allPrizes = 0;
        for (uint256 i = 0; i < games[_gameIndex].bigPrizeWinners.length; i++) {
            if (games[_gameIndex].bigPrizeWinners[i].win == 0) {
                allPrizes = allPrizes + games[_gameIndex].prizeFund;
            } else {
                allPrizes = allPrizes + games[_gameIndex].bigPrizeWinners[i].win;
            }
        }
        return allPrizes;
    }

    function requestPrize(uint256 _gameIndex, uint256 _ticketIndex) public gameIsNotReleased(_gameIndex) ticketIsNotReleased(_gameIndex, _ticketIndex) {
        uint256 multiplier = getMultiplier(_gameIndex, _ticketIndex);
        if (multiplier > 0) {
            uint256 win = multiplier * games[_gameIndex].tickets[_ticketIndex].amount;
            uint256 prizeFund = games[games[_gameIndex].referenceGame].prizeFund;
            if (win >= prizeFund) {
                games[games[_gameIndex].referenceGame].bigPrizeWinners.push(
                    BigPrizeWinner({
                        player : games[_gameIndex].tickets[_ticketIndex].player,
                        win : 0
                    }));
            } else if (win >= (prizeFund * FAST_WITHDRAW_PERCENTAGE_LIMIT / 100)) {
                games[games[_gameIndex].referenceGame].bigPrizeWinners.push(
                    BigPrizeWinner({
                        player : games[_gameIndex].tickets[_ticketIndex].player,
                        win : win
                    }));
            } else {
                token.safeTransfer(games[_gameIndex].tickets[_ticketIndex].player, win);
                games[games[_gameIndex].referenceGame].prizeFund = games[games[_gameIndex].referenceGame].prizeFund - win;
                PrizeSent(_gameIndex, _ticketIndex, win, games[_gameIndex].tickets[_ticketIndex].player);
            }
            games[_gameIndex].tickets[_ticketIndex].released = true;
        }
    }

    function getMultiplier(uint256 _gameIndex, uint256 _ticketIndex) public returns (uint256) {
        uint256 multiplier;
        uint256 referenceGameIndex = games[_gameIndex].referenceGame;
        if (isGameNumbersAreDefined(referenceGameIndex)) {
            uint8 mainBetMatches = getMatches(games[referenceGameIndex].winningNumbers, games[_gameIndex].tickets[_ticketIndex].mainBet);
            bool bonusBetGuessed = (games[referenceGameIndex].bonusNumber == games[_gameIndex].tickets[_ticketIndex].bonusBet);
            if (bonusBetGuessed == false) {
                if (mainBetMatches == 2) {
                    multiplier = 1;
                } else if (mainBetMatches == 3) {
                    multiplier = 20;
                } else if (mainBetMatches == 4) {
                    multiplier = 1000;
                } else if (mainBetMatches == 5) {
                    multiplier = 300000;
                }
            } else {
                if (mainBetMatches == 2) {
                    multiplier = 20;
                } else if (mainBetMatches == 3) {
                    multiplier = 200;
                } else if (mainBetMatches == 4) {
                    multiplier = 30000;
                } else if (mainBetMatches == 5) {
                    multiplier = games[referenceGameIndex].prizeFund / (10 ** 18);
                }
            }
        }
        return multiplier;
    }

    /**
    * 1.1 Check if bet has the right format:
    */
    function requireBetCorrect(uint8[5] _mainBet, uint8 _bonusBet) internal pure {
        require(_bonusBet > 0 && _bonusBet <= BONUS_BET_VARIANTS);
        uint8 prevNum = 0;
        for (uint8 i = 0; i < 5; i++) {
            require(_mainBet[i] > prevNum);
            require(_mainBet[i] <= MAIN_BET_VARIANTS);
            prevNum = _mainBet[i];
        }
    }

    /* ===================== HELPERS ===================== */
    /**
    * 3.3.1.1 If number in array
    */
    function inArray(uint8[BET_SIZE] _numberArr, uint8 _number) public pure returns (bool) {
        bool isInArray = false;

        for (uint i = 0; i < BET_SIZE; i++) {
            if (_number == _numberArr[i]) {
                isInArray = true;
                break;
            }
        }
        return isInArray;
    }

    // GETTERS:
    function getWinnerNumbersByGameIndex(uint256 _gameIndex) public returns (uint8[BET_SIZE], uint8) {
        return (games[_gameIndex].winningNumbers, games[_gameIndex].bonusNumber);
    }

    function getTicketBetByGameAndIndex(uint256 _gameIndex, uint256 _ticketIndex) public returns (uint8[BET_SIZE], uint8) {
        return (games[_gameIndex].tickets[_ticketIndex].mainBet, games[_gameIndex].tickets[_ticketIndex].bonusBet);
    }

    function getTicketsLength(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].tickets.length;
    }

    function getPrizeFund(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].prizeFund;
    }

    function getGameLength() public returns (uint256) {
        return games.length;
    }

    function getGameBlockNumber(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].block;
    }

    function getReferenceGame(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].referenceGame;
    }

    function getBigWinnersLength(uint256 _gameIndex) public returns (uint256) {
        return games[_gameIndex].bigPrizeWinners.length;
    }
}