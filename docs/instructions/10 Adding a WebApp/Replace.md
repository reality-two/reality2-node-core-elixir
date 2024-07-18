# Replace the existing WebApp

The existing WebApp was created using [Vite](https://vitejs.dev/), with the framework [Svelte](https://svelte.dev/) in [Typescript](https://www.typescriptlang.org/), and a library called [svelte-fomantic-ui](https://github.com/roycdaviesuoa/svelte-fomantic-ui).  The package management and compilation tool was [Yarn](https://yarnpkg.com/).

However, you can use whatever you like...

The place where the html, css and javascript files need to be placed is at:

```bash
reality2-node-core-elixir/apps/reality2_web/priv/static/sites/sentants
```

Replace the entire contents of the folder with whatever you prefer.

If you wish to use the frameworks and libraries described above, then the folder with the raw, uncompiled WebApp code is at:

```bash
reality2-node-core-elixir/web/sentants
```

Replace the code within with something more to your liking, then for convenience, once everything is set up in the above folder, you can compile and move the resulting WebApp to the correct place with the `build_webapp` script in the `scripts` folder (assuming you are using yarn and vite).  It takes one parameter - the name of the WebApp to build.

```bash
cd scripts
./build_webapp sentants
```

The reason for this slightly convoluted process is to remove the uncompiled WebApp and its libraries from the `priv/static` folder where it would normally reside, so that when the runtime version of a Reality2 node is created, it is not made needlessly large by including the uncompiled WebApp and its libraries.