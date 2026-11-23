// 外部の埋め込みの許可リスト（node --test test/）
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { matchEmbed, embedSize, embedHosts } from '../src/embed.js';

test('Google マップの埋め込みコードを通す', () => {
  const src = 'https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d3240.8!2d139.76!3d35.68';
  assert.equal(matchEmbed(src)?.provider.name, 'Google マップ');
  assert.ok(matchEmbed('https://www.google.com/maps/d/embed?mid=abc'));
  assert.ok(matchEmbed('https://www.google.com/maps/d/u/0/embed?mid=abc'));
  assert.ok(matchEmbed('https://maps.google.com/maps?q=tokyo&output=embed'));
});

test('動画や公開文書の埋め込みを通す', () => {
  const yt = matchEmbed('https://www.youtube.com/embed/dQw4w9WgXcQ?start=10');
  assert.equal(yt?.provider.name, 'YouTube');
  // YouTube はアプリ内で再生できないので、ブラウザの再生ページを開く
  assert.equal(yt.browserURL, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  assert.equal(matchEmbed('https://www.google.com/maps/embed?pb=1').browserURL, null);
  assert.ok(matchEmbed('https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ'));
  assert.ok(matchEmbed('https://player.vimeo.com/video/76979871'));
  assert.ok(matchEmbed('https://www.openstreetmap.org/export/embed.html?bbox=139.7,35.6,139.8,35.7&layer=mapnik'));
  assert.ok(matchEmbed('https://calendar.google.com/calendar/embed?src=ja.japanese%23holiday%40group.v.calendar.google.com'));
  assert.ok(matchEmbed('https://docs.google.com/presentation/d/e/2PACX-1vT/embed?start=false'));
  assert.ok(matchEmbed('https://docs.google.com/spreadsheets/d/e/2PACX-1vT/pubhtml'));
});

test('許可していない埋め込みは通さない', () => {
  for (const src of [
    'http://www.google.com/maps/embed?pb=1', // http
    'https://www.google.com/search?q=x', // 地図以外の Google
    'https://www.google.com/maps/place/Tokyo', // 埋め込み用ではない地図
    'https://www.google.com.evil.example/maps/embed', // 似た名前の別ホスト
    'https://evil.example/?https://www.google.com/maps/embed',
    'https://user:pass@www.google.com/maps/embed?pb=1',
    'https://www.google.com:8443/maps/embed?pb=1',
    'https://www.youtube.com/watch?v=abc', // 埋め込みではない
    'https://docs.google.com/forms/d/e/abc/viewform?embedded=true', // フォームは送信するので不可
    'javascript:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    '',
    null,
  ]) {
    assert.equal(matchEmbed(src), null, String(src));
  }
});

test('幅と高さの指定から縦横比を決める', () => {
  const maps = matchEmbed('https://www.google.com/maps/embed?pb=1').provider;
  assert.deepEqual(embedSize('600', '450', maps), { maxWidth: 600, ratio: [600, 450] });
  assert.deepEqual(embedSize('100%', '450', maps), { maxWidth: null, ratio: [4, 3] });
  assert.deepEqual(embedSize(null, null, maps), { maxWidth: null, ratio: [4, 3] });
  assert.deepEqual(embedSize('1', '99999', maps), { maxWidth: null, ratio: [4, 3] });
});

test('CSP の frame-src と許可リストが一致する', async () => {
  const html = await readFile(new URL('../viewer.html', import.meta.url), 'utf8');
  const policy = html.match(/http-equiv="Content-Security-Policy" content="([^"]+)"/)[1];
  const csp = policy.match(/frame-src ([^;]+);/)[1].trim().split(/\s+/);
  assert.deepEqual([...csp].sort(), embedHosts().map((h) => `https://${h}`).sort());
});
