import { identityFromSeed } from "../client/src/avatar.js";
import { nameFromSeed } from "../client/src/names.js";
import { writeFileSync } from "node:fs";

const seeds = Array.from({ length: 48 }, (_, i) => `critter-${i}-${(i * 2654435761) % 97}`);
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
</style><h1>HereBee — Fantasie-Krabbler (48 zufällige Seeds)</h1><div class="grid">${cells}</div>`;
writeFileSync("/Users/tom/ai/localizer/client/dist/creatures.html", html);
console.log("wrote creatures grid");
