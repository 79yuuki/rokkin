# 解説動画のソース

`docs/assets/rokkin-explainer.mp4` はこのフォルダのファイルから作っています（140 BPM・42小節・72秒）。

- `explainer.html` — 全シーン。`renderAt(t)` で任意の時刻のフレームを描く（背景は `../docs/assets/shader.js` と同じシェーダー）
- `music.py` — BGM を numpy で合成（キック・クラップ・ハット・ベース・コード・効果音）
- `render.js` — Playwright でシーンごとにフレームを撮り、ffmpeg にパイプして書き出す
- `preview.js` — 指定した時刻のフレームを JPEG で確認する

```bash
npm pack @fontsource/dela-gothic-one @fontsource/m-plus-rounded-1c   # fonts/ に woff2 を置く
cp ../docs/assets/shader.js . && cp ../docs/assets/icon-512.png icon.png
node render.js file://$PWD/explainer.html scenes 2 all
python3 music.py
ls scenes/*.mp4 | sed "s/^/file '/;s/$/'/" > list.txt
ffmpeg -f concat -safe 0 -i list.txt -i music2.wav -map 0:v -map 1:a -c:v copy -c:a aac -b:a 160k -shortest out.mp4
```
