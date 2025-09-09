---
layout: page
title: Tags
permalink: /tags/
---
<ul>
{% assign t = site.tags | sort %}
{% for tag in t %}
  <li><a href="#{{ tag[0] | slugify }}">{{ tag[0] }} ({{ tag[1].size }})</a></li>
{% endfor %}
</ul>
<hr/>
{% for tag in t %}
  <h3 id="{{ tag[0] | slugify }}">{{ tag[0] }}</h3>
  <ul>
    {% for post in tag[1] %}
      <li><a href="{{ post.url | relative_url }}">{{ post.title }}</a> — {{ post.date | date: "%b %d, %Y" }}</li>
    {% endfor %}
  </ul>
{% endfor %}
