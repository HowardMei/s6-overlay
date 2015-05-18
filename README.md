# s6 overlay [![Build Status](https://travis-ci.org/mubiic/s6-overlay.svg)](https://travis-ci.org/mubiic/s6-overlay)

The s6-overlay project is a series of init scripts and utilities as an overlay for Docker images with [s6 init suite](http://skarnet.org/software/s6/) as a process supervisor.

## Quickstart

Build the following Dockerfile and try this guy out:

```
FROM ubuntu
ADD https://github.com/mubiic/s6-overlay/releases/download/v1.A1.2/s6-overlay-portable-amd64.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-portable-amd64.tar.gz -C /
RUN apt-get update && \
    apt-get install -y nginx && \
    echo "daemon off;" >> /etc/nginx/nginx.conf
ENTRYPOINT ["/init"]
CMD ["nginx"]
```

```
docker-host $ docker build -t demo .
docker-host $ docker run --name s6demo -d -p 80:80 demo
docker-host $ docker top s6demo acxf
PID                 TTY                 STAT                TIME                COMMAND
3788                ?                   Ss                  0:00                \_ s6-svscan
3827                ?                   S                   0:00                | \_ foreground
3834                ?                   S                   0:00                | | \_ foreground
3879                ?                   S                   0:00                | | \_ nginx
3880                ?                   S                   0:00                | | \_ nginx
3881                ?                   S                   0:00                | | \_ nginx
3882                ?                   S                   0:00                | | \_ nginx
3883                ?                   S                   0:00                | | \_ nginx
3828                ?                   S                   0:00                | \_ s6-supervise
3829                ?                   S                   0:00                | \_ s6-supervise
3830                ?                   Ss                  0:00                | \_ s6-log
docker-host $ curl --head http://127.0.0.1/
HTTP/1.1 200 OK
Server: nginx/1.4.6 (Ubuntu)
Date: Thu, 26 Mar 2015 14:57:34 GMT
Content-Type: text/html
Content-Length: 612
Last-Modified: Tue, 04 Mar 2014 11:46:45 GMT
Connection: keep-alive
ETag: "5315bd25-264"
Accept-Ranges: bytes
```

## Features

* The s6-overlay provides proper `PID 1` functionality
  * You'll never have zombie processes hanging around in your container, they will be properly cleaned up.
* Multiple processes in a single container
* Able to operate in "The Docker Way"
* Usable with all base images - Ubuntu, CentOS, Fedora, and even Busybox.
* Distributed as a single .tar.gz file, to keep your image's number of layers small.

## The Docker Way?

One of the oft-repeated Docker mantras is "one process per container", but we disagree. There's nothing inherently *bad* about running multiple processes in a container. The more abstract "one *thing* per container" is our policy - a container should do one thing, such as "run a chat service" or "run gitlab." This may involve multiple processes, which is fine.

The other reason image authors shy away from process supervisors is they believe a process supervisor *must* restart failed services, meaning the Docker container will never die.

This does effectively break the Docker ecosystem - most images run one process that will exit when there's an error. By exiting on error, you allow the system administrator to handle failures however they prefer. If your image will never exit, you now need some alternative method of error recovery and failure notification.

Our policy is that if "the thing" fails, then the container should fail, too. We do this by determining which processes can restart, and which should bring down the container. For example, if `cron` or `syslog` fails, your container can most likely restart it without any ill effects, but if `ejabberd` fails, the container should exit so the system administrator can take action.

Our interpretation of "The Docker Way" is thus:

* Containers should do one thing
* Containers should stop when that thing stops

and our init system is designed to do exactly that! Your images will still behave like other Docker images and fit in with

## Overlay Usage

The project is distributed as a standard .tar.gz file, which you extract at the root of your image. Afterwards, set your `ENTRYPOINT` to `/init`

Right now, we recommend using Docker's `ADD` directive instead of running `wget` or `curl` in a `RUN` directive - Docker is able to handle the https URL when you use `ADD`, whereas your base image might not be able to use https, or might not even have `wget` or `curl` installed at all.

From there, you have a couple of options:

* Run your service/program as your image's `CMD`
* Write a service script

### Using `CMD`

Using `CMD` is a really convenient way to run take advantage of the s6-overlay. Your `CMD` can be given at build-time in the Dockerfile, or at runtime on the command line, either way is fine - it will be run under the s6 supervisor, and when it fails or exits, the container will exit. You can even run interactive programs under the s6 supervisor!

For example:

```
FROM busybox
ADD https://github.com/mubiic/s6-overlay/releases/download/v1.A1/s6-overlay-portable-amd64.tar.gz /tmp/
RUN gunzip -c /tmp/s6-overlay-portable-amd64.tar.gz | tar -xf - -C /
ENTRYPOINT ["/init"]
```

```
docker-host $ docker build -t s6demo .
docker-host $ docker run -ti s6demo /bin/sh
[fix-attrs.d] applying owners & permissions fixes...
[fix-attrs.d] 00-runscripts: applying...
[fix-attrs.d] 00-runscripts: exited 0.
[fix-attrs.d] done.
[cont-init.d] executing container initialization scripts...
[cont-init.d] done.
[services.d] starting services
[services.d] done.
/ # ps
PID   USER     COMMAND
    1 root     s6-svscan -t0 /var/run/s6/services
   21 root     foreground  if   /etc/s6/init/init-stage2-redirfd   foreground    if     s6-echo     [fix-attrs.d] applying owners & permissions fixes.
   22 root     s6-supervise s6-fdholderd
   23 root     s6-supervise s6-svscan-log
   24 nobody   s6-log -bp -- t /var/log/s6-uncaught-logs
   28 root     foreground  s6-setsid  -gq  --  with-contenv  /bin/sh  import -u ? if  s6-echo  --  /bin/sh exited ${?}  foreground  s6-svscanctl  -t
   73 root     /bin/sh
   76 root     ps
/ # exit
/bin/sh exited 0
docker-host $
```

### Docker images using this overlay

alpineproc && ubuntuproc in https://github.com/mubiic/dockerosbase

### Customizing `s6` behaviour

It is possible somehow to tweak `s6` behaviour by providing an already predefined set of environment variables to the execution context:

* `S6_LOGGING` (default = 0):
  * **`0`**: Outputs everything to stdout/stderr.
  * **`1`**: Uses an internal `catch-all` logger and persists everything on it, it is located in `/var/log/s6-uncaught-logs`. Nothing would be written to stdout/stderr.
* `S6_BEHAVIOUR_IF_STAGE2_FAILS` (default = 0):
  * **`0`**: Continue silently even if any script (fix-attrs or cont-init) has failed.
  * **`1`**: Continue but warn with an annoying error message.
  * **`2`**: Stop by sending a termination signal to the supervision tree.
* `S6_KILL_FINISH_MAXTIME` (default = 5000): The maximum time a script in `/etc/cont-finish.d` could take before sending a `KILL` signal to it. Take into account that this parameter will be used per each script execution, it's not a max time for the whole set of scripts.
* `S6_KILL_GRACETIME` (default = 3000): How much (in milliseconds) `s6` should wait to reap zombies before sending a `KILL` signal.

### Loading environment variables

If you'd like to write a shell script that references environment variables, use the `with-contenv` utility like so:

```sh
#!/usr/bin/with-contenv sh

printenv
```

### Writing environment variables

To write any new environment variables, use the `set-contenv` utility like so:

```sh
#!/usr/bin/with-contenv sh

set-contenv ENV_VAR_NAME env_var_value
```

The next time your script runs with `with-contenv`, your new environment variable will exist.

### Service scripts

s6init config dir by applying order<inside scripts applying order is according to naming sort,
 so 00-servicename0, 01-servicename1, 0N-servicenameN are the proper script names>:
/etc/fix-attrs.d      holds scripts to ensure files owners and permissions are correct
/etc/cont-init.d      holds one-time system scripts to execute container init before all
/etc/services.d       holds user services for long-lived daemon processes to be supervised:
/etc/services.d/*/run           hold service daemons running management scripts, treating s6-setuidgid like sudo
/etc/services.d/*/finish        hold service daemons exit clean up scripts
/etc/services.d/*/log/run       hold service daemons running logging scripts
/etc/services.d/*/log/finish    hold service daemons exit logging scripts
/etc/cont-finish.d    holds one-time system scripts to clean up container env before exit

s6init working dir:
/var/run/s6

## Credits
Most work have been done by https://github.com/glerchundi who is the original author of the scripts.
This is a pinpointed version v1.10.0.0 from https://github.com/just-containers/s6-overlay as v1.A1.0
Merged https://github.com/just-containers/s6-overlay/pull/53 from smebberson to support set-contenv as v1.A1.1 [Deprecated]  
***Now please use at least v1.A1.2 which is based on v1.10.0.3***  
Saved debugging tool from http://landley.net/aboriginal/downloads/binaries/extras/strace-x86_64
