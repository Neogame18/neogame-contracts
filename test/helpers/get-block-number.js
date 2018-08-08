const getBlockNumber = () => {
    return new Promise((resolve, reject) => {
        web3.eth.getBlockNumber((e, r) => {
            resolve(r)
        });
    });
};

module.exports = getBlockNumber;