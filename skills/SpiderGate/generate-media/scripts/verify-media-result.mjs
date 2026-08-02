#!/usr/bin/env node
/**
 * verify-media-result.mjs — confirm a generated media URL is REAL media, not a
 * 200-with-error-body. A generate call returning 200 is not proof the asset
 * rendered; fetch the stored URL and check its content-type. Paste the result.
 *
 * No dependencies — Node 18+ built-in fetch only.
 *
 * Usage:
 *   node verify-media-result.mjs --url https://media.cdn.spideriq.ai/gate-media/x.png
 *   node verify-media-result.mjs --url <url> --expect image   # image|video|audio
 *
 * Exits 0 if the URL resolves to media of the expected family; non-zero otherwise.
 */

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const k = argv[i].slice(2);
      out[k] = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
    }
  }
  return out;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.url) {
    console.error('ERROR: --url <media-url> is required.');
    process.exit(2);
  }
  let res;
  try {
    // HEAD first (cheap); some stores reject HEAD → fall back to a ranged GET.
    res = await fetch(args.url, { method: 'HEAD' });
    if (!res.ok) res = await fetch(args.url, { headers: { Range: 'bytes=0-0' } });
  } catch (e) {
    console.error(`ERROR: could not fetch ${args.url}: ${e.message}`);
    process.exit(1);
  }
  const ct = (res.headers.get('content-type') || '').toLowerCase();
  const len = res.headers.get('content-length');
  const family = ct.split('/')[0];
  const ok = res.ok && ['image', 'video', 'audio'].includes(family);

  console.log(`url:           ${args.url}`);
  console.log(`http status:   ${res.status}`);
  console.log(`content-type:  ${ct || '(none)'}`);
  console.log(`content-length:${len ? ' ' + len + ' bytes' : ' (unknown)'}`);

  if (!ok) {
    console.error(`\nNOT VERIFIED: this URL did not resolve to image/video/audio (got "${ct || 'nothing'}"). ` +
      `The generation may have failed silently — do NOT report success.`);
    process.exit(1);
  }
  if (args.expect && family !== args.expect) {
    console.error(`\nWRONG MODALITY: expected ${args.expect}/*, got ${family}/*.`);
    process.exit(1);
  }
  console.log(`\nOK — real ${family} at the stored URL.`);
}

main();
