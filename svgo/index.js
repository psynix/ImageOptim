"use strict";

const { optimize } = require('svgo');
const fs = require('fs');

try {
    const [mode, inputPath, outputPath] = process.argv.slice(2);
    if (!['0', '1'].includes(mode) || !inputPath || !outputPath) {
        throw new Error('Expected lossless/lossy mode (0/1), input SVG, and output path');
    }

    // Numeric/colour rewrites can change geometry or CSS attribute selectors.
    const plugins = ['removeComments', 'sortAttrs'];
    if (mode === '1') {
        plugins.push(
            { name: 'convertPathData', params: { floatPrecision: 3, applyTransforms: false } },
            { name: 'convertTransform', params: { floatPrecision: 3 } },
        );
    }

    const input = fs.readFileSync(inputPath, 'utf8');
    const result = optimize(input, { path: inputPath, plugins });
    // Preserve whitespace-sensitive content and animated geometry before rewriting paths.
    if (/<(?:[\w.-]+:)?(?:style|script|foreignObject|animate(?:Motion|Transform|Color)?|set)\b|<\?xml-stylesheet\b/i.test(input)) result.data = input;
    if (!result.data) throw new Error('Optimiser returned an empty SVG');
    fs.writeFileSync(outputPath, result.data);
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
