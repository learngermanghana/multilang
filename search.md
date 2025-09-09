---
layout: page
title: Search
permalink: /search/
---

<input type="text" id="search-input" placeholder="Search posts..." style="width:100%;padding:10px;border-radius:10px;border:1px solid #cbd5e1;">
<ul id="results-container" class="search-results"></ul>

<script src="https://cdn.jsdelivr.net/npm/simple-jekyll-search@1.11.1/dest/simple-jekyll-search.min.js"></script>
<script>
  SimpleJekyllSearch({
    searchInput: document.getElementById('search-input'),
    resultsContainer: document.getElementById('results-container'),
    json: '/search.json',
    searchResultTemplate: '<li><a href="{url}">{title}</a><span> — {date}</span></li>',
    noResultsText: '<li>No results</li>',
    limit: 20,
    fuzzy: true
  })
</script>

<style>
.search-results{list-style:none;padding-left:0;margin-top:12px}
.search-results li{padding:8px 0;border-bottom:1px solid #e2e8f0}
.search-results a{font-weight:700}
  .search-results span{color:#334155;margin-left:6px}
  </style>
