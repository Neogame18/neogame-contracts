const Crowdsale = artifacts.require('./Crowdsale.sol');
const Token = artifacts.require('./Token.sol');
const Game = artifacts.require('./TestNeoGame.sol');

const ether = require('./helpers/ether');
const waitAWhile = require('./helpers/wait-a-while');
const createRandomBet = require('./helpers/create-random-bet');
const getBlockNumber = require('./helpers/get-block-number');

const getAllEvents = (contract) => {
    return new Promise((resolve, reject) => {
        contract
            .allEvents({fromBlock: 0, toBlock: 'latest'})
            .get((err, res) => {
                if (err) {
                    reject(err);
                } else {
                    resolve(res);
                }
            });
    });
};

contract('Game', (accounts) => {
    const owner = accounts[0];
    const investor = accounts[1];
    const user = accounts[2];

    let crowdsaleContract;
    let tokenContract;
    let gameContract;

    let crowdsaleAddress;
    let tokenAddress;
    let gameAddress;

    it('Should deploy crowdsale', async() => {
        crowdsaleContract = await Crowdsale.deployed();
        crowdsaleAddress = crowdsaleContract.address;
        tokenAddress = await crowdsaleContract.token();
        tokenContract = Token.at(tokenAddress);
    });

    it('Should finalize crowdsale', async() => {
        const investment = ether(4);
        await waitAWhile();
        await crowdsaleContract.sendTransaction({
            value: investment,
            from: investor
        });


        const ownerBalanceBeforeFinalisation = await web3.eth.getBalance(owner);
        await crowdsaleContract.finalizeCrowdsale({ from: owner });

        const crowdsaleBalanceAfterFinalisation = await web3.eth.getBalance(crowdsaleAddress);
        const ownerBalanceAfterFinalisation = await web3.eth.getBalance(owner);
        assert.isOk(crowdsaleBalanceAfterFinalisation.eq(0));
        assert.isAbove(ownerBalanceAfterFinalisation.toNumber(), ownerBalanceBeforeFinalisation.toNumber());

        const investorTokens = await tokenContract.balanceOf(investor);
        const crowdsaleRate = await crowdsaleContract.rate.call();
        assert.isOk(crowdsaleRate.mul(investment).eq(investorTokens));
    });

    it('Should make a bet.', async() => {
        gameContract = await Game.deployed();
        gameAddress = gameContract.address;

        await tokenContract.transfer(gameAddress, ether(80000000));
        const BETS_QUANTITY = 5;
        const SINGLE_BET = ether(0.5);
        const ownerTokensBalance = await tokenContract.balanceOf(owner);
        const gameTokenBalance = await tokenContract.balanceOf(gameAddress);
        await tokenContract.approve(gameAddress, SINGLE_BET.mul(BETS_QUANTITY), {from: owner});
        let gameLength = await gameContract.getGameLength.call();
        assert.isOk(gameLength.eq(0));
        for (let i = 0; i < BETS_QUANTITY; i++) {
            const [mainBetNumbers, bonusBetNumber] = createRandomBet();
            await gameContract.bet(SINGLE_BET, mainBetNumbers, bonusBetNumber, {from: owner});
            const newOwnerTokensBalance = await tokenContract.balanceOf(owner);
            const newGameTokensBalance = await tokenContract.balanceOf(gameAddress);
            assert.isOk(newOwnerTokensBalance.eq(ownerTokensBalance.minus(SINGLE_BET.mul(i + 1))), 'Bet is transfering tokens from gamer\'s account');
            assert.isOk(newGameTokensBalance.eq(gameTokenBalance.plus(SINGLE_BET.mul(i + 1))), 'Bet is transfering tokens to game contract');
        }

        gameLength = await gameContract.getGameLength.call();
        assert.isOk(gameLength.eq(1));
        const ticketLength = await gameContract.getTicketsLength.call(0);
        assert.isOk(ticketLength.eq(BETS_QUANTITY));

    });

    it('Should create new game on bet if all bets are made', async() => {
        const currentEthereumBlockNumber = await getBlockNumber();
        const [mainBetNumbers, bonusBetNumber] = createRandomBet();
        await tokenContract.approve(gameAddress, ether(2), {from: owner});
        await gameContract.bet(ether(1), mainBetNumbers, bonusBetNumber, {from: owner});
        let gameLength = await gameContract.getGameLength.call();
        assert.isOk(gameLength.eq(1));
        await gameContract.__setBlockNumber(0, currentEthereumBlockNumber + 10);
        await gameContract.bet(ether(1), mainBetNumbers, bonusBetNumber, {from: owner});
        gameLength = await gameContract.getGameLength.call();
        assert.isOk(gameLength.eq(2));
    });

    it('Should setWinningNumbers', async() => {
        const currentEthereumBlockNumber = await getBlockNumber();
        const newGameBlockNumber = Math.max(currentEthereumBlockNumber - 20, 1);
        await gameContract.__setBlockNumber(0, newGameBlockNumber);
        await gameContract.setWinnerNumbers(0);
        const [mainBetNumbers, bonusBet] = await gameContract.getWinnerNumbersByGameIndex.call(0);
        const isMainBetNumbersDefined = mainBetNumbers.every((el) => {
            return !!el.toNumber();
        });
        const isBonusNumberDefined = !!bonusBet.toNumber();
        assert.isOk(isMainBetNumbersDefined && isBonusNumberDefined);
        const gameBalance = await tokenContract.balanceOf(gameAddress);
        const prizeFund = await gameContract.getPrizeFund.call(0);
        assert.isOk(prizeFund.gt(0));
        assert.isOk(prizeFund.lt(gameBalance));
    });

    it('Should send prizes on request prize', async() => {

        const BET_SIZE = ether(0.5);

        const MULTIPLIERS = {
            false2: 1,
            false3: 20,
            false4: 1000,
            false5: 300000,
            true2: 20,
            true3: 200,
            true4: 30000
        };

        const TICKET_WINS = {
            '1': 0,
            '2': MULTIPLIERS.false2,
            '3': MULTIPLIERS.false3,
            '4': MULTIPLIERS.false4,
            '5': MULTIPLIERS.false5,
            '6': MULTIPLIERS.true2,
            '7': MULTIPLIERS.true3,
            '8': MULTIPLIERS.true4
        };

        await tokenContract.approve(gameAddress, ether(4.5), {from: owner});
        // loose bet
        await gameContract.bet(BET_SIZE, [20, 21, 22, 23, 24], 6, {from: owner});

        // bets with different winning numbers and false bonus bet
        await gameContract.bet(BET_SIZE, [1, 2, 20, 21, 22], 1, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 21, 22], 1, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 4, 22], 1, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 4, 5], 1, {from: owner});

        // bets with different winning numbers and true bonus bet
        await gameContract.bet(BET_SIZE, [1, 2, 20, 21, 22], 6, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 21, 22], 6, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 4, 22], 6, {from: owner});
        await gameContract.bet(BET_SIZE, [1, 2, 3, 4, 5], 6, {from: owner});

        const currentEthereumBlockNumber = await getBlockNumber();
        const newGameBlockNumber = Math.max(currentEthereumBlockNumber - 20, 1);
        await gameContract.__setBlockNumber(0, newGameBlockNumber);
        await gameContract.__setWinnerNumbers(1, [1, 2, 3, 4, 5], 6);

        const allEvents = await getAllEvents(gameContract);
        const betEventsInSecondGame = allEvents.filter(log => {
            return log.event === 'NewBet' && log.args.gameIndex.eq(1);
        });

        const prizeFund = await gameContract.getPrizeFund.call(1);

        const multipliers = await Promise.all(betEventsInSecondGame.map(async (log, index) => {
            if (index > 0) {
                const winMultiplier = await gameContract.getMultiplier.call(log.args.gameIndex, log.args.ticketIndex);
                let checkValue = TICKET_WINS[index];
                if (index === 9) {
                    checkValue = prizeFund.div(ether(1)).floor();
                }
                assert.isOk(winMultiplier.eq(checkValue));
                return winMultiplier;
            }
        }));

        for (let i = 0; i < multipliers.length; i++) {
            const prize = multipliers[i] && multipliers[i].mul(BET_SIZE);
            if (prize && prize.gt(0)) {
                const winnerBalanceBeforeRequest = await tokenContract.balanceOf(owner);
                const prizeFundBeforeRequest = await gameContract.getPrizeFund.call(1);
                await gameContract.requestPrize(1, i);
                const winnerBalanceAfterRequest = await tokenContract.balanceOf(owner);
                const prizeFundAfterRequest = await gameContract.getPrizeFund.call(1);
                if (prize.lt(prizeFundBeforeRequest.mul(0.2))) {
                    assert.isOk(winnerBalanceAfterRequest.eq(winnerBalanceBeforeRequest.plus(prize)), `Winner balance after request #${i}`);
                    assert.isOk(prizeFundAfterRequest.eq(prizeFundBeforeRequest.minus(prize)), `Prize fund after request #${i}`);
                } else {
                    assert.isOk(winnerBalanceAfterRequest.eq(winnerBalanceBeforeRequest), `Delayed win #${i}`);
                    assert.isOk(prizeFundAfterRequest.eq(prizeFundBeforeRequest), `Delayed prizeFind #${i}`);
                }
            }
        }
    });

    it('Should send big wins on the second next game creation', async() => {
        let newGameBlockNumber = Math.max(await getBlockNumber() + 20, 1);
        await gameContract.__setBlockNumber(1, newGameBlockNumber);

        const gameLengthBefore = await gameContract.getGameLength.call();

        await tokenContract.approve(gameAddress, ether(2), {from: investor});
        await gameContract.bet(ether(1), [1, 2, 3, 4, 5], 6, {from: investor});
        await gameContract.bet(ether(1), [1, 2, 3, 4, 5], 7, {from: investor});

        await tokenContract.approve(gameAddress, ether(1.2), {from: owner});
        await gameContract.bet(ether(0.2), [1, 2, 3, 4, 5], 6, {from: owner});
        await gameContract.bet(ether(1), [1, 2, 3, 4, 5], 7, {from: owner});

        const gameLengthAfter = await gameContract.getGameLength.call();
        assert.isOk(gameLengthBefore.plus(1).eq(gameLengthAfter));

        newGameBlockNumber = Math.max(await getBlockNumber() + 20, 1);
        await gameContract.__setBlockNumber(2, newGameBlockNumber);

        const gameBalanceBeforeSendBigPrizes = await tokenContract.balanceOf(gameAddress);
        const winnerBalanceBeforeSendBigPrizes = await tokenContract.balanceOf(owner);

        const TRIGGER_BET = ether(1);

        await tokenContract.approve(gameAddress, TRIGGER_BET.mul(2), {from: investor});

        await gameContract.bet(TRIGGER_BET, [1, 2, 3, 4, 5], 6, {from: investor});
        await gameContract.bet(TRIGGER_BET, [1, 2, 3, 20, 21], 7, {from: investor});

        const gameLengthAfterAfter = await gameContract.getGameLength.call();
        const gameBalanceAfterSendBigPrizes = await tokenContract.balanceOf.call(gameAddress);
        const winnerBalanceAfterSendBigPrizes = await tokenContract.balanceOf.call(owner);

        assert.isOk(gameLengthAfterAfter.eq(gameLengthAfter.plus(1)));

        assert.isOk(gameBalanceAfterSendBigPrizes.lt(gameBalanceBeforeSendBigPrizes));
        assert.isOk(winnerBalanceAfterSendBigPrizes.gt(winnerBalanceBeforeSendBigPrizes));

        assert.isOk(gameBalanceBeforeSendBigPrizes
            .plus(TRIGGER_BET.mul(2))
            .minus(gameBalanceAfterSendBigPrizes)
            .eq(
                winnerBalanceAfterSendBigPrizes.minus(winnerBalanceBeforeSendBigPrizes)));
    });

    it('Should not set winning numbers in game if the current block > game.block + 256 blocks', async () => {
        let currentBlockNumber = await getBlockNumber();
        // Make sure we have > 256 blocks in our ethereum environment
        const loops = Math.ceil((257 - currentBlockNumber) / 2);
        for (let i = 0; i < loops; i++) {
            let bet = ether(1);
            await tokenContract.approve(gameAddress, bet, { from: owner });
            await gameContract.bet(bet, ...createRandomBet(), {from: owner});
            currentBlockNumber = await getBlockNumber();
        }
        const gameLength = await gameContract.getGameLength.call();
        const gameIndex = gameLength.minus(1).toNumber();
        await gameContract.__setBlockNumber(gameIndex, currentBlockNumber - 257);

        try {
            await gameContract.setWinnerNumbers(gameIndex);
            assert.fail('Set winning numbers should throw an error');
        } catch (err) {
            // this is predicted error
        }
        const [mainBetNumbers, bonusBet] = await gameContract.getWinnerNumbersByGameIndex.call(gameIndex);
        assert.equal(mainBetNumbers.reduce((acc, num) => {
            return acc + num.toNumber()
        }, 0), 0);
        assert.equal(bonusBet.toNumber(), 0);
    });

    let expiredGameIndex;
    let referenceGameIndex;
    it('Should reassign reference game to expired games after winning numbers being set', async() => {
        let bet = ether(0.2);
        await tokenContract.approve(gameAddress, bet, { from: owner });
        await gameContract.bet(bet, [1, 2, 3, 4, 5], 6, {from: owner});
        const gameLength = await gameContract.getGameLength.call();
        const gameIndex = gameLength.minus(1).toNumber();
        const newGameBlockNumber = Math.max(await getBlockNumber() - 20, 1);
        await gameContract.__setBlockNumber(gameIndex, newGameBlockNumber);
        await gameContract.setWinnerNumbers(gameIndex);
        expiredGameIndex = gameIndex - 1;
        referenceGameIndex = await gameContract.getReferenceGame.call(expiredGameIndex);
        assert.equal(referenceGameIndex.toNumber(), gameIndex);
    });

    it('Should release win from expired game', async() => {
        const allEvents = await getAllEvents(gameContract);
        const allBetsFromExpiredGame = allEvents.filter(log => {
            return log.event === 'NewBet' && log.args.gameIndex.eq(expiredGameIndex);
        });
        await gameContract.__setWinnerNumbers(referenceGameIndex, [1, 2, 3, 4, 5], 6);
        const prizeFund = await gameContract.getPrizeFund.call(referenceGameIndex);

        for (let i = 0; i < allBetsFromExpiredGame.length; i++) {
            const log = allBetsFromExpiredGame[i];

            const player = log.args.player;

            const winMultiplier = await gameContract.getMultiplier.call(log.args.gameIndex, log.args.ticketIndex);
            const prize = winMultiplier.mul(ether(1));
            const winnerBalanceBeforePrizeRequest = await tokenContract.balanceOf(player);
            const bigWinnersLengthBeforePrizeRequest = await gameContract.getBigWinnersLength.call(referenceGameIndex);
            await gameContract.requestPrize(expiredGameIndex, log.args.ticketIndex);
            if (prize.lt(prizeFund.mul(0.2))) {
                const winnerBalanceAfterPrizeRequest = await tokenContract.balanceOf(player);
                assert.isOk(winnerBalanceAfterPrizeRequest.eq(winnerBalanceBeforePrizeRequest.plus(prize)));
            } else {
                const bigWinnersLengthAfterPrizeRequest = await gameContract.getBigWinnersLength.call(referenceGameIndex);
                assert.isOk(bigWinnersLengthAfterPrizeRequest.eq(bigWinnersLengthBeforePrizeRequest.plus(1)));
            }
        }
    });
});