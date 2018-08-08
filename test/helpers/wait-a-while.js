const waitAWhile = (time = 4000) => {
    return new Promise(resolve => {
        setTimeout(resolve, time);
    });
};

module.exports = waitAWhile;