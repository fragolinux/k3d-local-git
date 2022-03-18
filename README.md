# Full setup of a Kubernetes K3D cluster managed by Flux on a local Git server

This script will automaGically create a single node Kubernetes [K3D](https://k3d.io) cluster on your development machine (tested on MacOS), managed in *GitOps way* by [Flux](https://fluxcd.io), which will interact with a fully local [Git server](https://hub.docker.com/r/jkarlos/git-server-docker/) running in a Docker container (external to the cluster). This all started as a Github Gist [here](https://gist.github.com/fragolinux/6ab59c4c7b0247c7d8b2aa5da13ae304).

You can use it in *interactive* mode passing "*-d*" switch on the command line.

On March 17, 2022 a live session of the *interactive* mode was taken and recorded by [Kingdon Barrett](https://www.linkedin.com/in/kingdon-barrett-73100a2) (Open Source Support Engineer at [Weaveworks](https://www.weave.works)), which collaborated by refactoring and reviewing the script code, so many thanks to him! :)

## Youtube recording of the live session on the *interactive* mode:

[![live session with Kingdon Barrett](https://img.youtube.com/vi/hNt3v0kk6ec/0.jpg)](https://www.youtube.com/watch?v=hNt3v0kk6ec)

## An Asciinema recording of the full setup in *unuttended* mode:

[![asciicast](https://asciinema.org/a/477968.png)](https://asciinema.org/a/477968)

![GitOps is the way...](https://i.imgflip.com/694d10.jpg)