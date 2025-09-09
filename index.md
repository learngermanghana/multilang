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
  <style>
    :root{
      --brand:#25317e;
      --bg:#f3f7fb;
      --ink:#1c2440;
      --muted:#64748b;
      --card:#ffffff;
      --ring:rgba(37,49,126,.18);
      --line:rgba(148,163,184,.35);
    }
    html,body{margin:0;padding:0;background:#fff;color:#0b1022;font-family:system-ui,-apple-system,Segoe UI,Roboto,Inter,Helvetica,Arial,sans-serif}
    .wrap{max-width:1100px;margin:0 auto;padding:0 18px}
    .hero{
      background: linear-gradient(180deg, var(--bg), rgba(243,247,251,0));
      border-top: 6px solid var(--brand);
      padding: 44px 0 22px;
    }
    .hero h1{margin:0 0 10px 0;font-size: clamp(28px, 4vw, 44px);line-height:1.1;color:var(--ink);font-weight:900}
    .hero p{margin:0 0 16px 0;color:var(--muted);font-size: clamp(16px, 2vw, 18px)}
    .cta{
      display:inline-block;background:var(--brand);color:#fff;text-decoration:none;
      padding:12px 16px;border-radius:12px;font-weight:800;border:1px solid rgba(37,49,126,.9);
      box-shadow:0 10px 22px var(--ring);
    }
    .cta:hover{filter:brightness(1.05)}
    .features{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px;margin:18px 0 8px}
    .feature{
      background:var(--card); border:1px solid var(--line); border-radius:14px; padding:14px 16px;
      box-shadow:0 6px 14px rgba(2,6,23,.06)
    }
    .feature h3{margin:0 0 6px 0; font-size:18px; color:var(--ink)}
    .feature p{margin:0;color:var(--muted);font-size:15px}
    .section{padding: 10px 0 28px}
    .section h2{margin:8px 0 10px 0;color:var(--ink);font-size:24px}
    .grid{
      display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));
      gap:14px;align-items:stretch
    }
    .card{
      background:#fff;border:1px solid var(--line);border-radius:14px;padding:14px 16px;
      box-shadow:0 6px 14px rgba(2,6,23,.06);display:flex;flex-direction:column;gap:8px
    }
    .card a{color:inherit;text-decoration:none}
    .card h3{margin:0;color:var(--ink);font-size:18px}
    .card p{margin:0;color:var(--muted);font-size:15px}
    .meta{font-size:13px;color:#8a97ab}
    .actions{display:flex;gap:10px;flex-wrap:wrap;margin-top:8px}
    .pill{
      display:inline-block;border:1px solid var(--line);padding:6px 10px;border-radius:999px;
      font-size:13px;color:#324051;text-decoration:none;background:#fff
    }
    footer{border-top:1px solid var(--line);padding:18px 0;color:#475569}
    .topnav{display:flex;gap:14px;align-items:center;justify-content:flex-end;padding:10px 0}
    .topnav a{color:var(--brand);text-decoration:none;font-weight:700}
    .topnav a:hover{text-decoration:underline}
  </style>
</head>
<body>

  <!-- Top nav (optional quick links) -->
  <div class="wrap">
    <nav class="topnav">
      <a href="{{ '/' | relative_url }}">Home</a>
      <a href="{{ '/about/' | relative_url }}">About</a>
      <a href="{{ '/search/' | relative_url }}">Search</a>
      <a href="{{ '/categories/' | relative_url }}">Categories</a>
      <a href="{{ '/tags/' | relative_url }}">Tags</a>
    </nav>
  </div>

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
      {% for post in site.posts limit:12 %}
      <article class="card">
        <a href="{{ post.url | relative_url }}">
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
  </section>

  <footer>
    <div class="wrap">
      © {{ site.time | date: "%Y" }} Learn Language Education Academy · <a href="mailto:learngermanghana@gmail.com">learngermanghana@gmail.com</a>
    </div>
  </footer>

</body>
</html>
