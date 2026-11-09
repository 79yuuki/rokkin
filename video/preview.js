const { chromium } = require('playwright');
(async () => {
  const [url, outDir, ...times] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  p.on('pageerror', e => console.log('pageerror:', e.message));
  await p.goto(url);
  await p.waitForFunction(() => window.fontsReady === true);
  await p.waitForTimeout(300);
  const tl = await p.evaluate(() => window.TIMELINE);
  for (const spec of times) {
    // spec "sceneId@localTime" or absolute seconds
    let t;
    if (spec.includes('@')) { const [id, lt] = spec.split('@'); t = tl.find(s => s.id === id).start + +lt; } else t = +spec;
    await p.evaluate(tt => window.renderAt(tt), t);
    await p.screenshot({ path: `${outDir}/f_${spec.replace('@', '_')}.jpg`, type: 'jpeg', quality: 80 });
  }
  console.log('total', await p.evaluate(() => window.TOTAL));
  await b.close();
})();
