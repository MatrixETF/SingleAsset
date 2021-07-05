const config = {
    solc: {
        version: '0.8.1',
        optimizer: {
            // PieFactory pushes contract size over limit. Consider reducing factory size
            enabled: true,
            runs: 200
        }
    },
}

export default config;