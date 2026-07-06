import { identityFromSeed } from "../client/src/avatar.js";
import { nameFromSeed } from "../client/src/names.js";
import { writeFileSync } from "node:fs";

const seeds = Array.from({ length: 48 }, (_, i) => `critter-${i}-${(i * 2654435761) % 97}`);
const escapeXml = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const svgInner = (svg: string) => svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>$/, "");

const cells = seeds
  .map((s) => {
    const id = identityFromSeed(s, nameFromSeed(s));
    return `<figure><div class="mk" style="--c:${id.color}"><div class="disc">${id.svg}</div></div><figcaption>${id.name}</figcaption></figure>`;
  })
  .join("");

const html = `<!doctype html><meta charset=utf8><style>
body{margin:0;background:#e7ede8;font:12px system-ui;padding:20px}
h1{font-size:18px}
.grid{display:grid;grid-template-columns:repeat(8,1fr);gap:18px 10px}
figure{margin:0;text-align:center}
.mk{width:56px;height:56px;margin:0 auto}
.disc{width:52px;height:52px;border-radius:50%;overflow:hidden;background:#171b22;border:3px solid var(--c);box-shadow:0 3px 10px rgba(0,0,0,.35)}
.disc svg{width:100%;height:100%;display:block}
figcaption{margin-top:5px;color:#333;font-size:10px}
</style><h1>HereBee — Bee Faces (48 zufaellige Seeds)</h1><div class="grid">${cells}</div>`;
writeFileSync("/Users/tom/ai/localizer/client/dist/creatures.html", html);

const sampleSeeds = seeds.slice(0, 16);
const sampleCells = sampleSeeds
  .map((s, i) => {
    const id = identityFromSeed(s, nameFromSeed(s));
    const x = 68 + (i % 4) * 220;
    const y = 86 + Math.floor(i / 4) * 142;
    return `<g transform="translate(${x} ${y})">
      <circle cx="36" cy="36" r="34" fill="#171b22" stroke="${id.color}" stroke-width="4"/>
      <svg x="0" y="0" width="72" height="72" viewBox="0 0 100 100">${svgInner(id.svg)}</svg>
      <text x="36" y="94" text-anchor="middle" fill="#e8edf2" font-family="system-ui, -apple-system, Segoe UI, sans-serif" font-size="11" font-weight="650">${escapeXml(id.name)}</text>
    </g>`;
  })
  .join("");
const sampleSvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 960 690" role="img" aria-labelledby="title desc">
  <title id="title">HereBee bee avatar samples</title>
  <desc id="desc">Sixteen deterministic bee faces generated from different seeds.</desc>
  <rect width="960" height="690" rx="0" fill="#0e1116"/>
  <text x="34" y="38" fill="#e8edf2" font-family="system-ui, -apple-system, Segoe UI, sans-serif" font-size="24" font-weight="760">HereBee Bee-Face Avatare</text>
  <text x="34" y="59" fill="#8a94a6" font-family="system-ui, -apple-system, Segoe UI, sans-serif" font-size="13">Seedbasiert, offline gerendert, keine Avatar-Library.</text>
  ${sampleCells}
</svg>`;
writeFileSync("/Users/tom/ai/localizer/client/public/brand/bee-avatar-samples.svg", sampleSvg);
console.log("wrote creatures grid");
