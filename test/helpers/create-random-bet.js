const randomNum = (min, max) => {
    return Math.floor(Math.random() * (max - min + 1) + min);
};

const createRandomMainBetArr = () => {
    const arr = [];
    while (arr.length < 5) {
        let newNumber = randomNum(1, 40);
        if (arr.indexOf(newNumber) === -1) {
            arr.push(newNumber);
        }
    }
    return arr.sort((a, b) => {
        return a - b;
    });
};

const createRandomBet = () => {
    return [createRandomMainBetArr(), randomNum(1, 21)];
};

module.exports = createRandomBet;