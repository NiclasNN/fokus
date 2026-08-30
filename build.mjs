// Bygger docs/ — bara det appen behöver. Inget index, ingen dev-server,
// inga verktyg. GitHub Pages serverar docs/ direkt från main.
// Kör: node build.mjs
import { rm, mkdir, cp, writeFile } from 'node:fs/promises';

const FILES = ['index.html', 'styles.css', 'app.js', 'sw.js', 'manifest.webmanifest'];

await rm('docs', { recursive: true, force: true });
await mkdir('docs', { recursive: true });
for (const f of FILES) await cp(f, `docs/${f}`);
await cp('icons', 'docs/icons', { recursive: true });
await writeFile('docs/.nojekyll', '');   // Pages ska inte köra Jekyll över filerna
console.log(`docs/ klar — ${FILES.length} filer + icons/`);
