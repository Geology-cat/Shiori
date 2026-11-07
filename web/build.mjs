// web/dist を生成する。dist はアプリに同梱するのでリポジトリにコミットする。
//   node build.mjs
import { build } from 'esbuild';
import { cp, mkdir, rm, readdir } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, 'dist');
const mods = join(here, 'node_modules');

await rm(dist, { recursive: true, force: true });
await mkdir(join(dist, 'katex/fonts'), { recursive: true });
await mkdir(join(dist, 'mermaid'), { recursive: true });

await build({
  entryPoints: [join(here, 'src/main.js')],
  outfile: join(dist, 'viewer.js'),
  bundle: true,
  minify: true,
  format: 'iife',
  target: ['safari17'],
  charset: 'utf8',
  legalComments: 'none',
  logLevel: 'info',
});

await cp(join(here, 'viewer.html'), join(dist, 'viewer.html'));
await cp(join(here, 'css'), join(dist, 'css'), { recursive: true });
await cp(join(here, 'themes'), join(dist, 'themes'), { recursive: true });

// KaTeX（woff2 のみ同梱して軽くする）
await cp(join(mods, 'katex/dist/katex.min.js'), join(dist, 'katex/katex.min.js'));
await cp(join(mods, 'katex/dist/katex.min.css'), join(dist, 'katex/katex.min.css'));
await cp(join(mods, 'katex/dist/contrib/mhchem.min.js'), join(dist, 'katex/mhchem.min.js'));
for (const file of await readdir(join(mods, 'katex/dist/fonts'))) {
  if (file.endsWith('.woff2')) {
    await cp(join(mods, 'katex/dist/fonts', file), join(dist, 'katex/fonts', file));
  }
}

await cp(join(mods, 'mermaid/dist/mermaid.min.js'), join(dist, 'mermaid/mermaid.min.js'));

// ヘルプから開く記法ガイド
const samples = join(here, '../samples');
await mkdir(join(dist, 'guide'), { recursive: true });
await cp(join(samples, '記法ガイド.md'), join(dist, 'guide/記法ガイド.md'));
await cp(join(samples, '読書サンプル.md'), join(dist, 'guide/読書サンプル.md'));
await cp(join(samples, 'images'), join(dist, 'guide/images'), { recursive: true });
