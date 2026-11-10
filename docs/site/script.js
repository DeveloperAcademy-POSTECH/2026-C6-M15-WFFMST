// 스크롤 등장과 동선 그리기. 자바스크립트가 없거나 움직임 줄이기를 켠 경우에는 최종 화면을 그대로 보여 준다.
(() => {
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || !('IntersectionObserver' in window)) return;

  document.documentElement.classList.add('motion');

  // 동선 길이를 재서 그리기 애니메이션을 준비한다
  const path = document.querySelector('.route__path');
  if (path) {
    const length = path.getTotalLength();
    path.style.setProperty('--len', length);
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.add('is-in');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -12% 0px', threshold: 0.15 });

  document.querySelectorAll('[data-reveal]').forEach((el) => observer.observe(el));
})();
