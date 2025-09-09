# Falowen Blog

This repository contains the source for the Falowen blog built with [Jekyll](https://jekyllrb.com/).

## Local development

1. Install [Ruby](https://www.ruby-lang.org/) and [Bundler](https://bundler.io/).
2. Install dependencies:
   ```bash
   bundle install
   ```
3. Start the development server:
   ```bash
   bundle exec jekyll serve
   ```
   The site will be available at http://localhost:4000 by default.

## Deployment

Run `bundle exec jekyll build` to generate the static site in the `_site/` directory. Pushes to the default branch trigger the CI workflow which builds the site and can be used to deploy to GitHub Pages or another static host.

## Contributing

1. Fork and clone the repository.
2. Create a feature branch for your work.
3. Follow the local development steps and ensure `bundle exec jekyll build` completes without errors.
4. Commit your changes and open a pull request.

Please make sure your changes pass CI before requesting a review.
