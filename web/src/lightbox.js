// 画像の拡大表示（クリックで開く／もう一度クリックか Esc で閉じる）
let box;

export function initLightbox() {
  box = document.getElementById('lightbox');
  box.addEventListener('click', close);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !box.hidden) {
      e.preventDefault();
      close();
    }
  });
}

export function openLightbox(img) {
  const clone = document.createElement('img');
  clone.src = img.currentSrc || img.src;
  clone.alt = img.alt;
  box.replaceChildren(clone);
  box.hidden = false;
}

function close() {
  box.hidden = true;
  box.replaceChildren();
}
