# Creating a new WebApp

The existing WebApp was created using [Vite](https://vitejs.dev/), with the framework [Svelte](https://svelte.dev/) in [Typescript](https://www.typescriptlang.org/), and a library called [svelte-fomantic-ui](https://github.com/roycdaviesuoa/svelte-fomantic-ui).  The package management and compilation tool was [Yarn](https://yarnpkg.com/).

In this example, we will use the same frameworks, however, you can use whatever you like.  It is assumed that you are working with the full version of `reality2-node-core-elixir` repository (as opposed to a release version).

The goal is to create a new WebApp that is available through a browser with the url:

```http
https://your.reality2.node/your_new_webapp
```

## Step 1 - Create the WebApp

The WebApps are stored in the web folder of the root folder of the repository.  To create one with the appropriate name and structure, we will use Vite.  In this example, we are going to create a demo for connecting IoT devices called `iotdemo`.  To create one with a different name, replace `iotdemo` with something else.

```bash
# Go into the web folder
cd web
# Create the WebApp called iotdemo as a svelte typescript project
yarn create vite iotdemo --template svelte-ts
# Get the libraries
cd iotdemo
yarn
```

## Step 2 - Compile the WebApp

You can compile and move the resulting WebApp to the correct place with the `build_webapp` script in the `scripts` folder.  It takes one parameter - the name of the WebApp to build.

```bash
cd scripts
./build_webapp iotdemo
```

## Step 3 - Test the WebApp

All going well, when you go to a browser window and open up `https://localhost/iotdemo`, you should see the default vite WebApp.

![](.images/vitewebapp.png)
