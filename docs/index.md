---
layout: default
home: true
permalink: /
title: c3pm — Package Manager for the C3 Programming Language
description: c3pm is a Nix-backed package manager and reproducible build environment for the C3 programming language and c3c compiler.
---

<header class="hero home-hero" id="top">
  <p class="eyebrow">Packages · Native libraries · Toolchains</p>
  <h1>Package management<br>for <span>C3.</span></h1>
  <p class="lede">c3pm is a Nix-backed package manager and reproducible build environment for the C3 programming language and <code>c3c</code> compiler.</p>
  <div class="hero-actions">
    <a class="button" href="{{ '/docs/getting-started/quickstart/' | relative_url }}">Quick start <span aria-hidden="true">→</span></a>
    <a class="text-link" href="{{ '/docs/getting-started/how-it-works/' | relative_url }}">How it works</a>
  </div>
</header>

<section class="home-install" aria-labelledby="home-install-title">
  <div class="home-install-header">
    <h2 id="home-install-title">Install c3pm</h2>
    <span>v{{ site.c3pm_version }} · Linux x86_64</span>
  </div>
  <div class="home-install-command">
{% highlight sh %}
curl --fail --location \
  https://c3pm.dev/install.sh | sh -
{% endhighlight %}
    <button class="copy-command" type="button" aria-label="Copy install command" title="Copy install command" hidden>
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false">
        <rect x="9" y="9" width="12" height="12" rx="2" />
        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
      </svg>
    </button>
    <span class="copy-feedback" role="status"></span>
  </div>
  <p>The installer uses your existing Nix installation or sets one up for you. <a href="{{ '/docs/getting-started/installation/' | relative_url }}">Installation guide <span aria-hidden="true">→</span></a></p>
</section>

<section class="home-demo" aria-labelledby="home-demo-title">
  <h2 id="home-demo-title">From a package to a running app</h2>
  <p>Watch a C3 project take shape: find raylib, add it, and run a windowed hello world.</p>
  <div class="home-demo-player">
    <script src="https://asciinema.org/a/U3d5pHHQY7fR1mgZ.js" id="asciicast-U3d5pHHQY7fR1mgZ" async="true"></script>
  </div>
  <p class="home-demo-links"><a href="{{ '/docs/getting-started/quickstart/' | relative_url }}">Follow the quick start <span aria-hidden="true">→</span></a><a href="https://asciinema.org/a/U3d5pHHQY7fR1mgZ">Open the recording</a></p>
</section>

<section class="home-guides" aria-labelledby="home-guides-title">
  <h2 id="home-guides-title">What are you building?</h2>
  <div class="home-guide-links">
    <a href="{{ '/docs/guides/packages/' | relative_url }}">
      <h3>Add a package <span aria-hidden="true">→</span></h3>
      <p>Find C3 libraries in a registry or add a source directly.</p>
    </a>
    <a href="{{ '/docs/guides/linking/' | relative_url }}">
      <h3>Link a library <span aria-hidden="true">→</span></h3>
      <p>Bring in native dependencies or another C3 project's library.</p>
    </a>
    <a href="{{ '/docs/guides/toolchains/' | relative_url }}">
      <h3>Choose your toolchain <span aria-hidden="true">→</span></h3>
      <p>Set the compiler and pin nixpkgs for your project.</p>
    </a>
    <a href="{{ '/docs/guides/bundles/' | relative_url }}">
      <h3>Ship your application <span aria-hidden="true">→</span></h3>
      <p>Bundle an executable and its runtime dependencies into one file.</p>
    </a>
  </div>
  <p>Want another complete example? Try the <a href="{{ '/docs/examples/sqlite/' | relative_url }}">SQLite application</a>. For syntax and options, see the <a href="{{ '/docs/reference/cli/' | relative_url }}">CLI reference</a>.</p>
</section>
