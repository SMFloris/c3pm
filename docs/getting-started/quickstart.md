---
title: "Quick start"
description: "Create a C3 project, install raylib, and run a windowed hello world with c3pm."
permalink: /docs/getting-started/quickstart/
---

Start with [Installation]({{ '/docs/getting-started/installation/' | relative_url }}) if c3pm is not installed. This example also uses an existing `c3c` command to create the initial project; subsequent builds run inside c3pm's environment.

## Build a raylib hello world

Create a new C3 project:

```sh
c3c init raylib_hello
cd raylib_hello
```

Search the registry and add raylib by its unique package name:

```sh
c3pm search raylib
c3pm add raylib
```

Replace `src/main.c3` with:

```c3
module raylib_hello;

import raylib6::rl;

fn void main()
{
	rl::init_window(800, 450, "raylib hello");
	defer rl::close_window();
	rl::set_target_fps(60);

	while (!rl::window_should_close())
	{
		rl::begin_drawing();
		rl::clear_background(rl::RAYWHITE);
		rl::draw_text("Hello, raylib!", 290, 210, 32, rl::DARKBLUE);
		rl::end_drawing();
	}
}
```

Build and run it inside the resolved development environment:

```sh
c3pm shell -- c3c run
```

The application opens an 800×450 window displaying “Hello, raylib!”. Press Escape or close the window to exit.

With the portable Nix backend, the first Nix operation initializes `nix-portable` and may fetch the inputs in [`.c3pm/nix/flake.lock`]({{ '/docs/reference/lock-file/' | relative_url }}). Later commands reuse that store and lock.
