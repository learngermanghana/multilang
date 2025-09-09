---
layout: page
title: Categories
permalink: /categories/
---
<ul>
{% assign cats = site.categories | sort %}
{% for c in cats %}
  <li><a href="#{{ c[0] | slugify }}">{{ c[0] }} ({{ c[1].size }})</a></li>
{% endfor %}
</ul>
<hr/>
{% for c in cats %}
  <h3 id="{{ c[0] | slugify }}">{{ c[0] }}</h3>
  <ul>
    {% for post in c[1] %}
      <li><a href="{{ post.url | relative_url }}">{{ post.title }}</a> — {{ post.date | date: "%b %d, %Y" }}</li>
    {% endfor %}
  </ul>
{% endfor %}
