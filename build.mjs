// Bygger dist/ — bara det appen behöver. Inget index, ingen dev-server,
// inga verktyg. Kör: node build.mjs
import { rm, mkdir, cp } from 'node:fs/promises';

const FILES = ['index.html', 'styles.css', 'app.js', 'sw.js', 'manifest.webmanifest'];

await rm('dist', { recursive: true, force: true });
await mkdir('dist', { recursive: true });
for (const f of FILES) await cp(f, `dist/${f}`);
await cp('icons', 'dist/icons', { recursive: true });
console.log(`dist/ klar — ${FILES.length} filer + icons/`);
