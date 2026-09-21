---
title: "Build c3pm from source"
description: "Build and test c3pm from its C3 source and preview documentation changes."
permalink: /docs/contributing/build-from-source/
---

Clone the repository first:

```sh
git clone https://github.com/SMFloris/c3pm.git
cd c3pm
```

With C3 {{ site.c3_version }} installed:

```sh
c3c build
c3c test
./build/c3pm --help
```

For release-style build commands on Linux x86_64, Linux ARM64, macOS ARM64, and source-only macOS Intel, see the [platform-specific instructions in the README](https://github.com/SMFloris/c3pm#build-from-source). macOS Intel is supported from source but omitted from the automated CI and release matrix.

Without a saved backend, a source build uses the `nix` command in `PATH`.

Select a persistent backend with `c3pm toolchain nix use`, or override it for one CI command:

```sh
C3PM_NIX=nix ./build/c3pm install
C3PM_NIX=nix ./build/c3pm bundle
```

`bundle` is Linux-only; omit that command on macOS.

To use a specific nix-portable executable instead:

```sh
C3PM_NIX_PORTABLE=/path/to/nix-portable ./build/c3pm install
```

Released c3pm executables never embed Nix or nix-portable.

## Preview the documentation

Documentation pages are Markdown files under `docs/`. With Nix available, run this from the repository root:

```sh
nix-shell -p rubyPackages.jekyll rubyPackages.kramdown-parser-gfm \
  --run 'jekyll serve --source docs --destination /tmp/c3pm-docs-preview --host 127.0.0.1 --port 4000'
```

Open `http://127.0.0.1:4000` in your browser. Jekyll rebuilds when you edit a page. This previews the site locally; the `/install.sh` redirect is applied by Cloudflare on deployment.

If you already have Ruby and Bundler, run `bundle install` inside `docs/`, followed by `bundle exec jekyll serve --destination ../_site`.

Add new pages to `docs/_data/navigation.yml`; both the sidebar and Previous/Next follow that order. Use each page's permalink when linking between documents.

## Crawl metadata

The production URL is set in `docs/_config.yml`. Each page's canonical URL and Open Graph URL use that origin and its permalink. `sitemap.xml` and `llms.txt` are generated from the same navigation list, so adding a documentation page includes it in both. `robots.txt` allows crawling and advertises the sitemap.

After deploying, check `/robots.txt`, `/sitemap.xml`, and `/llms.txt` on `https://c3pm.dev`, including any rules added by Cloudflare. The sitemap can also be submitted in Google Search Console; see [Google's sitemap submission instructions](https://developers.google.com/search/docs/crawling-indexing/sitemaps/build-sitemap#addsitemap).
