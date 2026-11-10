import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const renderer = process.env.RSVG_CONVERT || 'rsvg-convert';
const temporary = mkdtempSync(path.join(tmpdir(), 'imageoptim-svg-'));
const fixtures = readdirSync(path.join(directory, 'test/fixtures')).sort();
let originalBytes = 0, losslessBytes = 0, lossyBytes = 0;
let largestLossyDifference = 0;

function compareLossyPixels(before, after) {
    const pixels = [before, after].map((png, index) => {
        const input = path.join(temporary, `${index}.png`);
        const output = path.join(temporary, `${index}.bmp`);
        writeFileSync(input, png);
        execFileSync('/usr/bin/sips', ['--setProperty', 'format', 'bmp', input, '--out', output]);
        const bitmap = readFileSync(output);
        const width = bitmap.readInt32LE(18), height = Math.abs(bitmap.readInt32LE(22));
        const bits = bitmap.readUInt16LE(28);
        assert.ok(bits === 24 || bits === 32);
        const stride = Math.ceil(width * bits / 32) * 4;
        return bitmap.subarray(bitmap.readUInt32LE(10), bitmap.readUInt32LE(10) + height * stride);
    });
    assert.equal(pixels[0].length, pixels[1].length);
    let maximum = 0, total = 0;
    for (let index = 0; index < pixels[0].length; index++) {
        const difference = Math.abs(pixels[0][index] - pixels[1][index]);
        maximum = Math.max(maximum, difference);
        total += difference;
    }
    assert.ok(maximum <= 8 && total / pixels[0].length <= 0.05, 'Lossy rounding exceeded the fixture pixel-error bound');
    largestLossyDifference = Math.max(largestLossyDifference, maximum);
}
try {
    for (const name of fixtures) {
        const input = path.join(directory, 'test/fixtures', name);
        const original = readFileSync(input, 'utf8');
        originalBytes += Buffer.byteLength(original);
        for (const mode of ['0', '1']) {
            const output = path.join(temporary, `${mode}-${name}`);
            execFileSync(process.execPath, [path.join(directory, 'build/svgo.js'), mode, input, output]);
            const optimized = readFileSync(output, 'utf8');
            for (const [, id] of original.matchAll(/\bid="([^"]+)"/g)) assert.ok(optimized.includes(`id="${id}"`), `${name}: lost id ${id}`);
            for (const element of ['title', 'desc', 'style', 'image', 'symbol', 'use', 'animate']) {
                if (original.includes(`<${element}`)) assert.ok(optimized.includes(`<${element}`), `${name}: lost ${element}`);
            }
            if (/<animate/.test(original)) assert.equal(optimized, original, `${name}: changed animation geometry`);
            assert.equal(optimized.match(/viewBox="([^"]+)"/)?.[1], original.match(/viewBox="([^"]+)"/)?.[1], `${name}: changed viewBox`);
            for (const size of [96, 256]) {
                const args = ['--background-color', '#fff', '--width', String(size), '--height', String(size)];
                const before = execFileSync(renderer, [...args, input]);
                const after = execFileSync(renderer, [...args, output]);
                if (mode === '1' && name === 'paths.svg') compareLossyPixels(before, after);
                else assert.deepEqual(after, before, `${name}: mode ${mode} changed rendered pixels at ${size}px`);
            }
            if (mode === '0') losslessBytes += Buffer.byteLength(optimized);
            else lossyBytes += Buffer.byteLength(optimized);
        }
    }
    const invalid = path.join(temporary, 'invalid.svg');
    const rejected = path.join(temporary, 'invalid-output.svg');
    writeFileSync(invalid, '<svg><broken></svg>');
    assert.throws(() => execFileSync(process.execPath, [path.join(directory, 'build/svgo.js'), '0', invalid, rejected], { stdio: 'pipe' }));
    assert.throws(() => readFileSync(rejected));
    console.log(`${fixtures.length} SVG fixtures, ${fixtures.length * 4 - 2} exact raster comparisons and 2 bounded lossy comparisons passed (max channel delta ${largestLossyDifference}/255); ${originalBytes} -> ${losslessBytes} bytes lossless / ${lossyBytes} bytes lossy`);
} finally {
    rmSync(temporary, { recursive: true, force: true });
}
