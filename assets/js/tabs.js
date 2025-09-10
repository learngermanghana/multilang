if (document.querySelector('.tabs')) {
  document.addEventListener('DOMContentLoaded', function () {
    var tabLinks = document.querySelectorAll('.tab-links a');
    var tabs = document.querySelectorAll('.tab-content .tab');

    tabLinks.forEach(function (link) {
      link.addEventListener('click', function (e) {
        e.preventDefault();
        var target = this.getAttribute('href').substring(1);

        tabLinks.forEach(function (l) { l.parentElement.classList.remove('active'); });
        tabs.forEach(function (t) { t.classList.remove('active'); });

        this.parentElement.classList.add('active');
        document.getElementById(target).classList.add('active');
      });
    });
  });
}
