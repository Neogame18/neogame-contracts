const TestCrowdsale = artifacts.require('./Crowdsale.sol');
const TestToken = artifacts.require('./Token.sol');
const TestGame = artifacts.require('./TestNeoGame.sol');

const ether = function ether (n) {
    return new web3.BigNumber(web3.toWei(n, 'ether'));
};
const startTimestamp = Math.round(Date.now() / 1000) + 1;
const endTimestamp = startTimestamp + 10;
const rate = 4000;
const foundersToken = ether(100000000);
const goal = ether(12000);
const hardCap = ether(250000000);

let crowdsale,
    token,
    game;

module.exports = (deployer) => {
    return deployer.deploy(TestCrowdsale,
        startTimestamp, endTimestamp, rate, foundersToken, goal, hardCap)
        .then(() => {
            return TestCrowdsale.deployed();
        })
        .then(_crowdsale => {
            crowdsale = _crowdsale;
            return crowdsale.token.call();
        })
        .then((_token) => {
            token = _token;
            return deployer.deploy(TestGame, token);
        })
        .then((_game) => {
            game = _game;
        });
};
