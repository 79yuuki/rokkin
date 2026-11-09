// Renders the explainer scene by scene: each scene's frames are piped as JPEGs into its own ffmpeg encode.
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const fs = require('fs');
const FPS = 30;
(async () => {
  const [url, outDir, workersArg, onlyArg, limitArg] = process.argv.slice(2);
  const workers = +(workersArg || 4);
  const only = onlyArg && onlyArg !== 'all' ? onlyArg.split(',') : null;
  const limit = limitArg ? +limitArg : Infinity;
  const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const probe = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
  await probe.goto(url);
  const tl = await probe.evaluate(() => window.TIMELINE);
  await probe.close();
  const queue = tl.map((s, i) => ({ ...s, idx: i })).filter(s => !only || only.includes(s.id));
  async function work() {
    const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
    page.on('pageerror', e => console.log('pageerror:', e.message));
    await page.goto(url);
    await page.waitForFunction(() => window.fontsReady === true);
    await page.waitForTimeout(300);
    while (queue.length) {
      const s = queue.shift();
      const frames = Math.min(Math.round(s.dur * FPS), limit);
      const name = `${outDir}/scene_${String(s.idx).padStart(2, '0')}_${s.id}`;
      const ff = spawn('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
        '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20', '-pix_fmt', 'yuv420p', '-r', String(FPS), '-g', '60', `${name}.tmp.mp4`]);
      const done = new Promise((res, rej) => ff.on('exit', c => c === 0 ? res() : rej(new Error('ffmpeg ' + c))));
      const t0 = Date.now();
      for (let i = 0; i < frames; i++) {
        await page.evaluate(t => window.renderAt(t), s.start + i / FPS);
        const buf = await page.screenshot({ type: 'jpeg', quality: 92 });
        if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      }
      ff.stdin.end();
      await done;
      fs.renameSync(`${name}.tmp.mp4`, `${name}.mp4`);
      console.log(`${s.id}: ${frames} frames in ${((Date.now() - t0) / 1000).toFixed(1)}s`);
    }
    await page.close();
  }
  await Promise.all(Array.from({ length: workers }, work));
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
