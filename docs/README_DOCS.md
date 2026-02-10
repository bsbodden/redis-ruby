# redis-ruby Documentation

This directory contains the source files for the redis-ruby documentation site, built with Jekyll and YARD.

## Documentation Structure

```
docs/
├── _config.yml           # Jekyll configuration
├── _layouts/             # Page layouts
│   ├── default.html      # Base layout
│   ├── home.html         # Home page layout
│   ├── page.html         # Regular page layout
│   └── guide.html        # Guide page layout
├── _includes/            # Reusable components
│   ├── header.html       # Site header
│   ├── sidebar.html      # Navigation sidebar
│   └── footer.html       # Site footer
├── _pages/               # Static pages
│   ├── getting-started.md
│   ├── performance.md
│   ├── contributing.md
│   └── redis-stack/      # Redis Stack module docs
├── _guides/              # In-depth guides
│   ├── connections.md
│   ├── connection-pools.md
│   ├── pipelines.md
│   ├── pubsub.md
│   ├── transactions.md
│   ├── lua-scripting.md
│   ├── cluster.md
│   ├── sentinel.md
│   ├── client-side-caching.md
│   └── distributed-locks.md
├── _examples/            # Code examples
│   ├── basic-usage.md
│   ├── connection-pooling.md
│   ├── pipelining.md
│   ├── pubsub.md
│   └── redis-stack.md
├── assets/               # Static assets
│   ├── css/
│   ├── js/
│   └── images/
├── _site/                # Generated site (gitignored)
│   └── api/              # YARD API documentation
├── Gemfile               # Jekyll dependencies
└── index.md              # Home page
```

## Building the Documentation

### Prerequisites

- Ruby 3.2+ (3.3+ recommended)
- Bundler

### Install Dependencies

```bash
# Install main project dependencies (includes YARD)
bundle install

# Install Jekyll dependencies
cd docs
bundle install
cd ..
```

### Generate API Documentation

```bash
# Generate YARD API documentation
bundle exec rake docs:api

# Or directly with YARD
bundle exec yard doc
```

### Build Jekyll Site

```bash
# Build the Jekyll site
bundle exec rake docs:build

# Or directly with Jekyll
cd docs
bundle exec jekyll build
```

### Serve Locally

```bash
# Serve with live reload
bundle exec rake docs:serve

# Or directly with Jekyll
cd docs
bundle exec jekyll serve --livereload
```

Then open http://localhost:4000/redis-ruby/ in your browser.

### Generate All Documentation

```bash
# Generate both API docs and Jekyll site
bundle exec rake docs:all
```

### Clean Generated Files

```bash
# Remove generated documentation
bundle exec rake docs:clean
```

## Writing Documentation

### Adding a New Guide

1. Create a new file in `_guides/` with `.md` extension
2. Add front matter:

```yaml
---
layout: guide
title: Your Guide Title
description: Brief description of the guide
difficulty: beginner|intermediate|advanced
reading_time: 10 minutes
---
```

3. Write your content in Markdown
4. Add the guide to navigation in `_config.yml`

### Adding a New Example

1. Create a new file in `_examples/` with `.md` extension
2. Add front matter:

```yaml
---
layout: example
title: Your Example Title
permalink: /examples/your-example/
---
```

3. Write your example with code blocks
4. Link from `_pages/examples.md`

### Adding a New Page

1. Create a new file in `_pages/` with `.md` extension
2. Add front matter:

```yaml
---
layout: page
title: Your Page Title
permalink: /your-page/
---
```

3. Write your content
4. Add to navigation in `_config.yml` if needed

## Deployment

The documentation is automatically built and deployed to GitHub Pages when changes are pushed to the `main` branch.

The GitHub Actions workflow (`.github/workflows/docs.yml`) handles:
1. Generating YARD API documentation
2. Building the Jekyll site
3. Deploying to GitHub Pages

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on contributing to the documentation.

## License

The documentation is licensed under the same MIT license as redis-ruby.

