# Installation

Warning - this is not yet usable by people who are not happy getting into the Linux command line.  If you need help, find a linux guru and entice them with pizza and coffee to give you a hand.

The instructions below are for installing and using the reference implementation of the Reality2 Node that has been built in Elixir.

### Pre-compiled

There are some versions of Reality2 Nodes pre-compiled, ready for use.  This is the easy way to get going...

To use, head over to the [releases](https://github.com/roycdavies/reality2/releases) section and download the appropriate version.  Further instructions are there.

### Compile-it-yourself

If there is no version for your platform and OS, then you'll have to do it the hard way...

#### Step 1

- Read the documentation.  If you've got this far, great - keep reading...

#### Step 2

- Clone the GIT repository.  If that doesn't make sense to you, then you should go find that Linux guru.
- I suggest creating a folder called Reality2, and cloning the repository into that folder.  You will end up with a folder inside the Reality2 folder called 'reality2' (which I usually then rename to 'Reality2').  In the main Reality2 folder, you can create useful files for private API keys without them ending up in the repository.  For example, below, we create a file to hold your OpenAI API key.

```bash
mkdir Reality2
cd Reality2
git clone https://github.com/roycdavies/reality2.git
mv reality2 Reality2
echo sk-[YOUR OPENAI API KEY HERE] > OPENAI_API_KEY.txt
cd Reality2
```

#### Step 3

- Make a note of the working directory for this installation.  You will need this later.

```bash
pwd
/Users/rdav031/Development/Reality2/Reality2
```



#### Step 4

- Install Erlang and Elixir.  I have found that the installations via [asdf](https://asdf-vm.com/) are good, and you can get the latest versions of Erlang and Elixir.  Be warned, though, that Erlang is compiled from source using this method.  This is mostly fine, except when trying to install on a small wearable linux computer with limited processing power as it can take some time.
- You may need to install some libraries to compile Erlang:

```bash
sudo apt install libssl-dev automake autoconf libncurses5-dev
```

```bash
asdf plugin add erlang
asdf install erlang latest

# Make sure you are in the main directory for Reality2
# eg cd Reality2
asdf global erlang latest
asdf local erlang latest

asdf plugin add elixir
asdf install elixir latest

# Make sure you are in the main directory for Reality2
# You should already be there after installing Erlang
asdf global elixir latest
asdf local elixir latest
```

#### Step 5

- Install the Elixir plugins.  The framework we are using is the [Pheonix Framework](https://www.phoenixframework.org/), with [Absinthe](https://absinthe-graphql.org/) for the GraphQL.

```bash
mix deps.get
```

#### Step 6

- Build the web interface.  This uses yarn for the building (rather than npm), and various libraries, including [svelte-fomantic-ui](https://github.com/roycdaviesuoa/svelte-fomantic-ui) also made by the author of Reality2.  So, obviously, you'll have to have installed [yarn](https://yarnpkg.com/) first.
- It's possible you might need to install the latest version of Node.JS.  You can use ASDF for that too.

```bash
asdf plugin add nodejs
asdf install nodejs latest

# Make sure you are in the web/sentants directory for Reality2
# eg: cd web/sentants
asdf global nodejs latest
asdf local nodejs latest

npm install -g yarn
```

```bash
cd scripts
./web_build
```

#### Step 7

- Run the Reality2 node.  Presently, this is only set up for developer mode.  So, back out again to the main level of the respository, and set it going.

```bash
# Still in the scripts folder.
./run_as_dev
```

What you should see:

```bash
[info] Running Reality2Web.Endpoint with cowboy 2.10.0 at 0.0.0.0:4002 (http)
[info] Running Reality2Web.Endpoint with cowboy 2.10.0 at 0.0.0.0:4001 (https)
[info] Access Reality2Web.Endpoint at https://localhost:4001
Erlang/OTP 26 [erts-14.2.3] [source] [64-bit] [smp:10:10] [ds:10:10:10] [async-threads:1] [jit]

Interactive Elixir (1.16.2) - press Ctrl+C to exit (type h() ENTER for help)
[debug] Tzdata polling for update.
[debug] Tzdata polling shows the loaded tz database is up to date.
iex(1)>
```

Congratulations, you now have a Reality2 node up and running.  Feels good doesn't it?  Your life is coming together.

#### Step 8

- Have a look at it.  Open a browser and go to `https://lcoalhost:4001`.  Click past the info about this being a potentially dangerous site due to self-signed certificates.  You accept the risk, right? (if you want, you can make your own certificates - a good idea actually - that can be a bit of homework).

![](.images/sNoMR8fMaujOQ.png)

- Not surprisingly, there is nothing to see, because you haven't loaded any Sentants yet, but we know it is up and running, and the web interface is working.

#### Troubleshooting

- There are many places where this can fail.  Because you are compiling and running from source, you have to have all the libraries and tools in place first, and then you can run the Reality2 Node. 
- The release versions are precompiled and packaged to be ready to run for different architectures.