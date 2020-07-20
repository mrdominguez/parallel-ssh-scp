### Table of Contents

[Synopsis](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#synopsis)  
[Sample Output](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#sample-output)  
[Installation](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#installation)  
[Setting Credentials](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#setting-credentials)  
[Usage](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#usage)  
[How-To](https://github.com/mrdominguez/parallel-ssh-scp/blob/master/README.md#how-to)

## Synopsis

AUTHOR: Mariano Dominguez  
<marianodominguez@hotmail.com>  
https://www.linkedin.com/in/marianodominguez

VERSION: 3.1

FEEDBACK/BUGS: Please contact me by email.

`mdssh.pl` (as in my initials, MD) is an asynchronous parallel SSH/SCP command-line utility that does not require setting up SSH keys. It enables process concurrency and calls `sshexp.pl` and `scpexp.pl` in the background to connect to remote hosts (one host per process) via `ssh` or `scp` respectively.

*Sudo* operations that require password input are also supported either by setting `-sudo[=sudo_user]` (*preferred method*) or using the `sudo` command.

## Sample Output

Check the status of the `ntpd` service on *kube-master*, *kube-node1*, *kube-node2* and *localhost*:
```
[mdom@localhost ~]$ mdssh -s='kube-master kube-node{1,2} localhost' 'service ntpd status'
[kube-node2] (auth) EOF
ssh: connect to host kube-node2 port 22: Connection refused
[localhost] [14481] -> OK
Redirecting to /bin/systemctl status  ntpd.service
● ntpd.service - Network Time Service
   Loaded: loaded (/usr/lib/systemd/system/ntpd.service; enabled; vendor preset: disabled)
   Active: active (running) since Tue 2020-06-02 23:26:22 EDT; 14min ago
  Process: 11870 ExecStart=/usr/sbin/ntpd -u ntp:ntp $OPTIONS (code=exited, status=0/SUCCESS)
 Main PID: 11871 (ntpd)
   CGroup: /system.slice/ntpd.service
           └─11871 /usr/sbin/ntpd -u ntp:ntp -g
[kube-node1] [14479] -> Error (rc=3)
Redirecting to /bin/systemctl status ntpd.service
● ntpd.service - Network Time Service
   Loaded: loaded (/usr/lib/systemd/system/ntpd.service; disabled; vendor preset: disabled)
   Active: inactive (dead)
[kube-master] [14482] -> OK
Redirecting to /bin/systemctl status ntpd.service
● ntpd.service - Network Time Service
   Loaded: loaded (/usr/lib/systemd/system/ntpd.service; disabled; vendor preset: disabled)
   Active: active (running) since Tue 2020-06-02 23:15:10 EDT; 25min ago
  Process: 16684 ExecStart=/usr/sbin/ntpd -u ntp:ntp $OPTIONS (code=exited, status=0/SUCCESS)
 Main PID: 16685 (ntpd)
    Tasks: 1
   Memory: 616.0K
   CGroup: /system.slice/ntpd.service
           └─16685 /usr/sbin/ntpd -u ntp:ntp -g
-----
Number of hosts: 4
~
OK: 2 | kube-master localhost
~
Error (rc=3): 1 | kube-node1
~
Error (rc=255): 1 | kube-node2
[mdom@localhost ~]$
```

Restart the `ntpd` service and use verbose output (`-v`), which is especially useful for tracking progress when managing hundreds of hosts:
```
[mdom@localhost ~]$ mdssh -v -sudo -s='kube-master kube-node{1,2} localhost' 'service ntpd restart'
threads = 10
timeout = 20 seconds
o = 1
olines = 10
username = mdom
Password file /home/mdom/ssh_pass found
Sudoing to user root
tcount = 25
ttime = 5 seconds
-----
[kube-master] [15192] process_1 forked
[kube-node1] [15193] process_2 forked
[kube-node2] [15195] process_3 forked
[localhost] [15197] process_4 forked
[kube-node2] (auth) EOF
ssh: connect to host kube-node2 port 22: Connection refused
[kube-node2] [15195] process_3 exited (Pending: 3 | Forked: 4 | Completed: 1/4 -25%- | OK: 0 | Error: 1)
[localhost] [15203] -> OK
Redirecting to /bin/systemctl restart  ntpd.service
[localhost] [15197] process_4 exited (Pending: 2 | Forked: 4 | Completed: 2/4 -50%- | OK: 1 | Error: 1)
[kube-node1] [15201] -> OK
Redirecting to /bin/systemctl restart ntpd.service
[kube-node1] [15193] process_2 exited (Pending: 1 | Forked: 4 | Completed: 3/4 -75%- | OK: 2 | Error: 1)
[kube-master] [15202] -> OK
Redirecting to /bin/systemctl restart ntpd.service
[kube-master] [15192] process_1 exited (Pending: 0 | Forked: 4 | Completed: 4/4 -100%- | OK: 3 | Error: 1)
All processes completed
-----
Number of hosts: 4
~
OK: 3 | kube-master kube-node1 localhost
~
Error (rc=255): 1 | kube-node2
[mdom@localhost ~]$
```

## Installation

These utilities are written in Perl and have been tested using *Perl 5.1x.x* on *RHEL 6/7*, as well as *macOS Sierra* and after.

Automation for authentication is managed through the **Expect.pm** module. **IO::Prompter** is used for username/password prompting and the interactive mode functionality in `sshexp.pl` requires **IO::Stty**.

Use [cpan](http://perldoc.perl.org/cpan.html) to install the aforementioned modules; alternately, download them from the [CPAN Search Site](http://search.cpan.org/) for manual installation.

**IMPORTANT: Set the `$shell_prompt` variable in `sshexp.pl` to a regex matching the end of `$PS1` (prompt shell variable) for Expect to correctly catch command execution termination as the default value `'\][\$\#] $'` may not always work**.

The following is an example of an unattended installation script for RHEL-based distributions:
```
#!/bin/bash

sudo yum -y install git cpan gcc openssl openssl-devel

REPOSITORY=parallel-ssh-scp
cd; git clone https://github.com/mrdominguez/$REPOSITORY

cd $REPOSITORY
chmod +x *.pl
ln -s mdssh.pl mdssh
ln -s sshexp.pl sshexp
ln -s scpexp.pl scpexp

cd; grep "PATH=.*$REPOSITORY" .bashrc || echo -e "\nexport PATH=\"\$HOME/$REPOSITORY:\$PATH\"" >> .bashrc

echo | cpan
. .bashrc

perl -MCPAN -e 'my $c = "CPAN::HandleConfig"; $c->load(doit => 1, autoconfig => 1); $c->edit(prerequisites_policy => "follow"); $c->edit(build_requires_install_policy => "yes"); $c->commit'
cpan Expect IO::Stty IO::Prompter

mdssh -help
echo "Run 'source ~/.bashrc' to refresh environment variables"
```

If you run into the issue below, particularly in *RHEL 6*, install or update these packages: `nss curl libcurl`.

```
$ git clone https://github.com/mrdominguez/parallel-ssh-scp
Initialized empty Git repository in /home/mdom/parallel-ssh-scp/.git/
error:  while accessing https://github.com/mrdominguez/parallel-ssh-scp/info/refs

fatal: HTTP request failed
$
```

## Setting Credentials

The username can be set by using the `-u` option in the command line or the `$SSH_USER` environment variable. If not set, the default username is the value of the environtment variable `$USER`.

The password can be passed by setting the `-p` option or the `$SSH_PASS` environment variable to:
- The actual password string (**not recommended**).
- A file containing the password.

Both username and password values are optional. If no value is provided, there will be a prompt for one, and if the password is not set, its value will be undefined.

## Usage

**mdssh.pl**
```
Usage: mdssh.pl [-help] [-version] [-u[=username]] [-p[=password]]
    [-sudo[=sudo_user]] [-sshOpts=ssh_options] [-timeout=n] [-threads=n]
    [-scp [-tolocal] [-multiauth] [-r] [-d=target_path] [-meter]]
    [-tcount=throttle_count] [-ttime=throttle_time]
    [-o[=0|1] -olines=n -odir=path] [-v [-timestamp]] (-s="host1 host2 ..." | -f=hosts_file) <command|source_path>

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-)
     -p : Password or path to password file (default: undef)
     -sudo : Sudo to sudo_user and run <command> (default: root)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 seconds)
     -threads : Number of concurrent processes (default: 10)
     -scp : Copy <source_path> from local host to @remote_hosts:<target_path>
     -tolocal : Copy @remote_hosts:<source_path> to <target_path> in local host
                The remote hostnames will be appended to <target_path> as a directory
                If permissions allow it, non-existent local directories will be created
     -multiauth : Always authenticate when password prompted (default: single authentication attempt)
     -r : Recursively copy entire directories
     -d : Target path (default: $HOME)
     -meter : Display scp progress (default: disabled)
     -tcount : Number of forked processes before throttling (default: 25)
     -ttime : Throttling time (default: 5 seconds)
     -o : (Not defined) Buffer the output and display it after command completion
          (0) Do not display command output
          (1) Display command output as it happens
     -olines : Ignore -o and display the last n lines of buffered output (default: 10 | full output: 0)
     -odir : Local directory in which the command output will be stored as a file (default: $PWD -current folder-)
             If permissions allow it, the directory will be created if it does not exit
     -v : Enable verbose messages / progress information
     -timestamp : Display timestamp
     -s : Space-separated list of hostnames (brace expansion supported)
     -f : File containing hostnames (one per line)
     Set -tcount or -ttime to 0 to disable throttling
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     Enable -multiauth along with -tolocal when <source_path> uses brace expansion
     Encase <command> in quotes (single argument)
```

NOTES:
- Once a process is running, a timeout occurs when the executed command does not output anything after the `-timeout` value is reached.
- Unless overridden by the SSH *ConnectTimeout* option, the system's TCP connect timeout value will be used (the default for Linux is 20 seconds). To change it, set `-sshOpts` as follows  `-sshOpts='-o ConnectTimeout=10'` (in seconds).
- Both `-f` and `-s` can be used at the same time.
- Lines containing the `#` character in the hosts file will be skipped.

**sshexp.pl**
```
Usage: sshexp.pl [-help] [-version] [-u[=username]] [-p[=password]] [-sudo[=sudo_user]] [-sshOpts=ssh_options] 
    [-timeout=n] [-o[=0|1] -olines=n -odir=path] [-v] [-d] <host> [<command>]

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-)
     -p : Password or path to password file (default: undef)
     -sudo : Sudo to sudo_user and run <command> (default: root)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 seconds)
     -o : (Not defined) Display command output as it happens
          (0) Do not display command output
          (1) Buffer the output and display it after command completion (useful for concurrent execution)
     -olines : Ignore -o and display the last n lines of buffered output (default: 10 | full output: 0)
     -odir : Directory in which the command output will be stored as a file (default: $PWD -current folder-)
     -v : Enable verbose messages
     -d : Expect debugging	 
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     Encase <command> in quotes to pass it as a single argument
     Omit <command> for interactive mode
```
**scpexp.pl**
```
Usage: scpexp.pl [-help] [-version] [-u[=username]] [-p[=password]] [-sshOpts=ssh_options] 
    [-timeout=n] [-tolocal] [-multiauth] [-r] [-v] [-d] [-q] <source_path> <host> [<target_path>]

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-)
     -p : Password or path to password file (default: undef)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 seconds)
     -tolocal : Copy from remote host to local host (default: local -> remote)
                If permissions allow it, non-existent local directories in <target_path> will be created
     -multiauth : Always authenticate when password prompted (default: single authentication attempt)
     -q : Quiet mode disables the progress meter (default: enabled)
     -r : Recursively copy entire directories
     -v : Enable verbose messages
     -d : Expect debugging
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     If omitted, <target_path> default value is $HOME
     Enable -multiauth along with -tolocal when <source_path> uses brace expansion
```

## How-To

(Assuming that `$SSH_USER` and `$SSH_PASS` have been set)

* Check the OS (RHEL) and kernel version on the remote hosts:

	`mdssh.pl -f=hosts 'cat /etc/redhat-release; uname -r'`

* Execute `df -h` and send the output to a file in the local `./df_output` directory:

	`mdssh.pl -f=hosts -odir=df_output 'df -h'`

* Push `package.rpm` to `/var/local/tmp` using 3 copy processes:

	`mdssh.pl -threads=3 -f=hosts -scp -d=/var/local/tmp package.rpm`

* Install (as root) the package, set timeout to 5 minutes:

	`mdssh.pl -timeout=300 -f=hosts -sudo 'rpm -ivh /var/local/tmp/package.rpm'`

* Delete the rpm file:

	`mdssh.pl -f=hosts 'rm /var/local/tmp/package.rpm'`

* Pull `/var/log/messages` to the local `./remote_files` directory:

	`mdssh.pl -f=hosts -scp -tolocal -d=remote_files /var/log/messages`
