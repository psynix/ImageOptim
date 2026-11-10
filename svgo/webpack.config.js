"use strict";
const path = require("path");

module.exports = {
    cache: true,
    context: __dirname,
    entry: "./index.js",
    output: {
        path: path.join(__dirname, "build"),
        filename: "svgo.js",
    },
    target: "node16",
    mode: "production",
    optimization: {
        minimize: true,
    },
};
