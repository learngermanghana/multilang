document.addEventListener('DOMContentLoaded', () => {
  const features = document.querySelectorAll('.feature');
  features.forEach(el => el.classList.add('reveal'));

  const observer = new IntersectionObserver((entries, obs) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('in-view');
        obs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1 });

  features.forEach(el => observer.observe(el));
});
