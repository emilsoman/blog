# Emil Soman's Blog

A personal blog built with 11ty (Eleventy) and Liquid templating.

## Project Structure

```
blog/
├── _includes/          # Layout templates
│   └── layout.html     # Main layout template
├── _site/              # Generated site (ignored in git except for favicon.png and app.css)
├── post/               # Blog posts
│   ├── post.json       # Post collection configuration
│   └── *.md            # Individual post files
├── index.html          # Homepage
└── .gitignore          # Git ignore rules
```

## Getting Started

Serve locally:

```bash
npx @11ty/eleventy --serve
```

## Writing Posts

Create new posts in the `post/` directory as Markdown files with front matter:

```markdown
---
title: "Your Post Title"
date: 2025-10-26
---

Your post content here...
```

Posts are automatically:

- Tagged with "post" collection
- Sorted by date (newest first)

## Customization

- **Styling**: Edit `app.css` for custom styles
- **Layout**: Modify `_includes/layout.html` for template changes
- **Post settings**: Update `post/post.json` for collection configuration

## Deployment

The `_site/` directory contains the generated static files ready for deployment to any static hosting service.
Hosted on Cloudflare Pages.
