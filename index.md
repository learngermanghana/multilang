---
layout: null
---

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Falowen Blog</title>
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  {%- comment -%} Minima head + your custom head {%- endcomment -%}
  {%- include head.html -%}
  {%- include head-custom.html -%}
  <link rel="stylesheet" href="{{ '/assets/css/main.css' | relative_url }}">
</head>
<body>

  <!-- Top nav (optional quick links) -->
  {% include topnav.html %}

  <!-- Hero -->
  <header class="hero">
    <div class="wrap">
      <h1>Falowen Blog</h1>
      <p>Your German conversation partner online, with tips for A1–C1, exam prep guidance, vocabulary strategies, and product updates from Learn Language Education Academy.</p>
      <a class="cta" href="https://falowen.app" target="_blank" rel="noopener">Try Falowen</a>
    </div>
  </header>

  <!-- Feature highlights -->
  <section class="wrap section">
    <h2>Highlights</h2>
    <div class="features">
      <div class="feature">
        <h3>Exam-focused</h3>
        <p>Practical guidance aligned to Goethe A1–C1 tasks.</p>
      </div>
      <div class="feature">
        <h3>Vocabulary that sticks</h3>
        <p>Short examples and routines that build habits.</p>
      </div>
      <div class="feature">
        <h3>Teacher + App</h3>
        <p>Assignments, feedback, and daily practice in one place.</p>
      </div>
    </div>
  </section>

  <!-- Latest posts grid -->
  <section class="wrap section">
    <h2>Latest articles</h2>
    <div class="grid">
      {% for post in paginator.posts %}
      <article class="card">
        <a href="{{ post.url | relative_url }}">
          {% if post.image %}
          <img class="post-card-img" src="{{ post.image }}" alt="{{ post.title }}" />
          {% endif %}
          <h3>{{ post.title }}</h3>
          {% if post.excerpt %}
          <p>{{ post.excerpt | strip_html | truncate: 120 }}</p>
          {% endif %}
        </a>
        <div class="meta">
          {{ post.date | date: "%b %d, %Y" }}
          {% if post.tags %} · {{ post.tags | join: ", " }}{% endif %}
        </div>
        <div class="actions">
          <a class="pill" href="{{ post.url | relative_url }}">Read</a>
          {% if post.categories and post.categories.size > 0 %}
            <a class="pill" href="{{ '/categories/#' | append: post.categories[0] | slugify | relative_url }}">{{ post.categories[0] }}</a>
          {% endif %}
        </div>
      </article>
      {% endfor %}
    </div>
    <nav class="pagination">
      {% if paginator.previous_page %}
        <a class="newer" href="{{ paginator.previous_page_path | relative_url }}">&laquo; Newer Posts</a>
      {% endif %}
      {% if paginator.next_page %}
        <a class="older" href="{{ paginator.next_page_path | relative_url }}">Older Posts &raquo;</a>
      {% endif %}
    </nav>
  </section>

  {% include newsletter.html %}

  <footer>
    <div class="wrap">
      © {{ site.time | date: "%Y" }} Learn Language Education Academy
      · <a href="mailto:learngermanghana@gmail.com">learngermanghana@gmail.com</a>
      · <a href="https://instagram.com/lleaghana" target="_blank" rel="noopener">Instagram</a>
      · <a href="https://tiktok.com/@lleaghana" target="_blank" rel="noopener">TikTok</a>
      · <a href="https://youtube.com/@LLEAGhana" target="_blank" rel="noopener">YouTube</a>
      · <a href="https://linkedin.com/in/lleaghana" target="_blank" rel="noopener">LinkedIn</a>
      · <a href="https://register.falowen.app" target="_blank" rel="noopener">Register</a>
    </div>
  </footer>
  <script>
    (function() {
      const toggle = document.getElementById('theme-toggle');
      const stored = localStorage.getItem('theme');
      const prefers = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
      const theme = stored || prefers;
      document.body.classList.add(theme);
      toggle.addEventListener('click', function() {
        const next = document.body.classList.contains('dark') ? 'light' : 'dark';
        document.body.classList.remove('light', 'dark');
        document.body.classList.add(next);
        localStorage.setItem('theme', next);
      });
    })();
  </script>
</body>
</html>
