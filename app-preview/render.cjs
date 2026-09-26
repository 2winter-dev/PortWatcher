const { Resvg } = require('@resvg/resvg-js');
const fs = require('fs');

const [svg, out, w] = process.argv.slice(2);
if (!svg || !out) {
  console.error('usage: node render.cjs <in.svg> <out.png> [width]');
  process.exit(1);
}
const svgData = fs.readFileSync(svg, 'utf8');
const opts = w ? { fitTo: { mode: 'width', value: Number(w) } } : {};
const resvg = new Resvg(svgData, opts);
const png = resvg.render().asPng();
fs.writeFileSync(out, png);
console.log('wrote', out, png.length, 'bytes');
