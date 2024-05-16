# Folder structure

The main Reality2 folder contains several subfolders with code and examples.  These are:

- **apps**
  The main Elixir code for the Reality2 Node.  Here, you can find the inbuilt plugins such as the Pathing Name System and Authentication, which are mostly stubs for later work.

- **config**
  More stuff related to the Elixir code for the Reality2 Node.  Don't change things in here unless you know what you are doing.

- **definitions**
  Some (possibly out of date) graphql and yaml definitions for sentants.  The stuff in the python folder is more recent.

- **deps**
  The dependencies for the Elixir code for the Reality2 Node.  These are built when you run `mix deps.get`

- **docs**
  Automatically generated files documenting the Elixir code, and these files you are now reading.

- **logos**
  Some possible logos.  Any graphic designers out there want to suggest something better, let me know.

- **demos**
  Various demos and client apps for various platforms
  - **node-red**
    See the section on node-red.  Here is the definition file for a node-red demo.
  - **python**
    Python demos and example Sentant definition files.
  - **SBC**
    Some code related to Single Board Computers (such as the Unihiker and the Raspberry Pi).
  - **XR**
    Presently working on a Godot-based visualiser.  Might also do one for ThreeJS and Unity.

- **web**
  Link into the web pages for Sentants.

- **scripts**
  Various scripts for running the Reality2 node and making runtime versions.  Switch to this directory before running as some files are created relative to this folder.
