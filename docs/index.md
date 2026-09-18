---
layout: default
title: c3pm — C3 Package Manager
description: Reproducible C3 projects, powered by Nix.
---

<section class="doc-section is-active" id="overview" data-section="overview">
<header class="hero" id="top">
  <p class="eyebrow">Package management for C3</p>
  <h1>A complete package manager for C3</h1>
  <p class="lede">Manage C3 packages, native libraries, the compiler, and nixpkgs together. c3pm turns standard C3 metadata and <code>vendor.c3pm</code> configuration into a reproducible environment for every project.</p>
  <div class="hero-actions">
    <a class="button" href="#install">Install c3pm</a>
    <a class="text-link" href="https://github.com/SMFloris/c3pm">View on GitHub <span aria-hidden="true">→</span></a>
  </div>
</header>

<div class="feature-grid">
  <div class="feature">
    <span class="feature-number">01</span>
    <h3>Unified dependencies</h3>
    <p>Manage C3 packages and native libraries through one project workflow.</p>
  </div>
  <div class="feature">
    <span class="feature-number">02</span>
    <h3>Reproducible toolchains</h3>
    <p>Pin the compiler, nixpkgs, and source revisions for consistent builds everywhere.</p>
  </div>
  <div class="feature">
    <span class="feature-number">03</span>
    <h3>Ship one file</h3>
    <p>Package your app and its runtime dependencies into one portable Linux executable.</p>
  </div>
</div>

<div class="home-intro">
  <p>Released c3pm binaries are self-contained. You can run c3pm without an existing C3 compiler or compatible system libc, then use either your system Nix installation or a managed <code>nix-portable</code> backend for builds.</p>
</div>

<div class="home-facts" aria-label="Current platform and defaults">
  <div>
    <strong>Current platform</strong>
    <span>Linux x86_64</span>
  </div>
  <div>
    <strong>Default toolchain</strong>
    <span>C3 0.8.3 · nixpkgs-unstable</span>
  </div>
</div>

<nav class="section-pagination" aria-label="Section navigation">
  <a class="section-page next" href="#quick-start">
    <span>Next</span>
    <strong>Quick start</strong>
  </a>
</nav>

</section>

<!-- README_SECTIONS -->
