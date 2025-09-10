(function() {
  const tabLists = document.querySelectorAll('[role="tablist"]');
  tabLists.forEach(list => {
    const tabs = list.querySelectorAll('[role="tab"]');
    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const targetId = tab.getAttribute('aria-controls');
        if (!targetId) return;

        tabs.forEach(t => {
          t.setAttribute('aria-selected', 'false');
          const id = t.getAttribute('aria-controls');
          if (!id) return;
          const panel = document.getElementById(id);
          if (!panel) return;
          panel.setAttribute('hidden', '');
          panel.classList.remove('fx-tab-panel--active');
        });

        tab.setAttribute('aria-selected', 'true');
        const panel = document.getElementById(targetId);
        if (!panel) return;
        panel.removeAttribute('hidden');
        requestAnimationFrame(() => {
          panel.classList.add('fx-tab-panel--active');
        });
      });
    });
  });
})();
