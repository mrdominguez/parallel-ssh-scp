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

VERSION: 6.6

FEEDBACK/BUGS: Please contact me by email.

`mdssh.pl` (as in my initials, MD) is an asynchronous parallel SSH/SCP command-line utility that does not require setting up SSH keys. It enables process multithreading and calls `sshexp.pl` or `scpexp.pl` to connect to remote hosts (one host per process) through `ssh` and `scp` respectively.

*Sudo* operations that require password input are also supported either by setting `-sudo[=sudo_user]` or using the `sudo` command.

The latest release contains performance enhancements, specifically, optimizations to the concurrency management logic (among other code improvements).

It is compatible with the Okta ASA ScaleFT client when using the `-via=bastion` option, which works for both SSH and SCP protocols. See Okta documentation [Use Advanced Server Access with SSH bastions](https://help.okta.com/asa/en-us/Content/Topics/Adv_Server_Access/docs/setup/ssh.htm). The `-via` option can be overriden on a per host basis by adding the bastion/proxy server to the host name separated by a comma:

```
[remote_user@]host,[bastion_user@]bastion
```

Further, SSH allows connecting to remote hosts though a proxy (or bastion) with [ProxyJump](https://www.redhat.com/sysadmin/ssh-proxy-bastion-proxyjump). Set `-sshOpts` or simply use the equivalent `-proxy` option:

```
-sshOpts='-J user@bastion:port'
-proxy=user@bastion:port
```

Note that commands in `mdssh.pl` are interpreted twice; therefore, escaped characters need to be double escaped (`\\\`). The following yields identical results:

```
sshexp host 'VAR=value; echo $VAR'
mdssh -s=host 'VAR=value; echo \$VAR'
```

```
sshexp host "awk '{print \$3 \"\t\" \$4}' file"
mdssh -s=host "awk '{print \\\$3 \\\"\t\\\" \\\$4}' file"
```

Pushing a command to the background can be done by appending ampersand (`&`). This works just fine if no output is returned other than `[job_id] pid`, because additional output can make the Expect library unreliable. Thus, when enabling background mode (`-bg`), the exit code of the command will not be checked. Instead, once the command gets sent, the script will end and return `OK (BG) | RC=100`.

A space-separated list of host files (globbing supported) can be used:

```
mdssh -f='/path/to/host_files/* /additional/host_file.txt' -s='192.168.0.10{0..9}' <command>
```

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
[kube-node1] [14479] -> Error (RC=3)
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

OK: 2 | kube-master localhost

Error (RC=3): 1 | kube-node1

Error (RC=255): 1 | kube-node2
-----
[mdom@localhost ~]$
```

Restart the `ntpd` service and use verbose output (`-v`), which is especially useful for tracking progress when managing hundreds of hosts:
```
[mdom@localhost ~]$ mdssh -v -sudo -s='kube-master kube-node{1,2} localhost' 'service ntpd restart'
threads = 10
timeout = 20 s
out = 1
olines = 10
username = mdom
Password file /home/mdom/ssh_pass found
Sudoing to user root
tcount = 25
ttime = 5 s
-----
[kube-master] [15192] process_1 forked
[kube-node1] [15193] process_2 forked
[kube-node2] [15195] process_3 forked
[localhost] [15197] process_4 forked
[kube-node2] (auth) EOF
ssh: connect to host kube-node2 port 22: Connection refused
[kube-node2] [15195] process_3 exited (Pending: 3 | Forked: 4 | 1/4 -25%- | OK: 0 | Error: 1)
[localhost] [15203] -> OK
Redirecting to /bin/systemctl restart  ntpd.service
[localhost] [15197] process_4 exited (Pending: 2 | Forked: 4 | 2/4 -50%- | OK: 1 | Error: 1)
[kube-node1] [15201] -> OK
Redirecting to /bin/systemctl restart ntpd.service
[kube-node1] [15193] process_2 exited (Pending: 1 | Forked: 4 | 3/4 -75%- | OK: 2 | Error: 1)
[kube-master] [15202] -> OK
Redirecting to /bin/systemctl restart ntpd.service
[kube-master] [15192] process_1 exited (Pending: 0 | Forked: 4 | 4/4 -100%- | OK: 3 | Error: 1)
All processes completed
-----
Number of hosts: 4

OK: 3 | kube-master kube-node1 localhost

Error (RC=255): 1 | kube-node2
-----
[mdom@localhost ~]$
```

## Installation

These utilities are written in *Perl* and have been tested using version *5.1x.x* on *RHEL 6/7*, as well as *macOS Sierra (10.12)* and after.

Automation for authentication is managed with the **Expect.pm** module. **IO::Prompter** is used for username/password prompting and the interactive mode functionality in `sshexp.pl` requires **IO::Stty**.

Use [cpan](http://perldoc.perl.org/cpan.html) to install the aforementioned modules or download them from the [CPAN Search Site](http://search.cpan.org/) for manual installation.

**IMPORTANT! Set the `$shell_prompt` variable in `sshexp.pl` to a regex matching the end of `$PS1` (prompt shell variable) for Expect to correctly catch command execution termination, as the default value (that is, `'\][\$#] $'`) may not always work. Alternatively, use the `-prompt` option from the command line.**

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

The username can be set as `username@host`, by using the `-u` option in the command line, or the `$SSH_USER` environment variable (in that order of precedence). If not set, the default username is the value of the environtment variable `$USER`.

The password can be passed by setting the `-p` option or the `$SSH_PASS` environment variable to:
- The actual password string (**not recommended**).
- A file containing the password.

Both username and password values are optional. If no value is provided, there will be a prompt for one, and if the password is not set, its value will be undefined.

Okta/sft (`-via`) is the default mode when dealing with bastion/proxy hosts. To enable ProxyJump, set the `-proxy` option. One difference between `-via` and `-proxy` regarding authentication is that, in the absence of `-bu` (bastion/proxy user) and/or `-ru` (remote user), the latter can take the `-u` option to access both proxy and remote hosts. In Okta mode, `-u` gets ignored since the underlying Okta credentials are utilized instead.

## Usage

**mdssh.pl**
```
Usage: mdssh.pl [-help] [-version] [-u[=username]] [-p[=password]]
    [-sudo[=sudo_user]] [-bg] [-prompt=regex]
    [-via|proxy=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]
    [-sshOpts=ssh_options] [-timeout=n] [-threads=n]
    [-scp [-tolocal] [-multiauth] [-r] [-target=target_path] [-meter]]
    [-tcount=throttle_count] [-ttime=throttle_time]
    [-out[=0|1] -olines=n -odir=path] [-et|minimal] [-v|timestamp]
    (-s='[user1@]host1[,$via1|proxy1] [user2@]host2[,$via2|proxy2] ...' -f='host_file1 host_file2 ...') <command|source_path>

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-, ignored when using -via or Okta credentials)
     -p : Password or path to password file (default: undef)
     -sudo : Sudo to sudo_user and run <command> (default: root)
     -bg : Background mode (exit after sending command)
     -prompt : Shell prompt regex (default: '\][\$\#] $' )
     -via : Bastion host for Okta ASA sft client (default over -proxy)
     -proxy : Proxy host for ProxyJump (leave empty to enable over -via)
       -bu : Bastion user
       -ru : Remote user
             (default: Okta username -sft login-)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 s)
     -threads : Number of concurrent processes (default: 10)
     -scp : Copy <source_path> from local host to @remote_hosts:<target_path>
       -tolocal : Copy @remote_hosts:<source_path> to <target_path> in local host
                  The remote hostnames will be appended to <target_path> as a directory
                  If permissions allow it, non-existent local directories will be created
       -multiauth : Always authenticate when password prompted (default: single authentication attempt)
       -r : Recursively copy entire directories
       -target : Target path (default: '.' -dot, or current directory-)
       -meter : Display scp progress (default: disabled)
     -tcount : Number of forked processes before throttling (default: 25)
     -ttime : Throttling time (default: 5 s)
     -out : (Not defined) Buffer the output and display it after command completion
            (0) Do not display command output
            (1) Display command output as it happens
     -olines : Display the last n lines of buffered output (default: 10 | full output: 0, implies undefined -out)
     -odir : Local directory in which the command output will be stored as a file (default: $PWD -current folder-)
             If permissions allow it, the directory will be created if it does not exit
     -et : Hide execution time
     -minimal : Hide process termination tracking in non-verbose mode (implies -et)
     -v : Enable verbose messages
     -timestamp : Display time (implies -v)
     -s : Space-separated list of hostnames (brace expansion supported)
     -f : Space-separated list of files containing hostnames, one per line (globbing supported)
     Set -tcount or -ttime to 0 to disable throttling
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     Enable -multiauth along with -tolocal when <source_path> uses brace expansion
     Encase <command> in quotes (single argument)
```

NOTES:
- Once a process is running, a timeout occurs when the executed command does not output anything after the `-timeout` value is reached.
- Unless overridden by the SSH *ConnectTimeout* option, the system's TCP connect timeout value will be used (the default for Linux is 20 seconds). To change it, set `-sshOpts` as follows  `-sshOpts='-o ConnectTimeout=10'` (in seconds).
- Both `-f` and `-s` can be set at the same time.
- Lines containing the `#` character in the hosts file will be skipped.

**sshexp.pl**
```
Usage: sshexp.pl [-help] [-version] [-u[=username]] [-p[=password]]
    [-sudo[=sudo_user]] [-bg] [-prompt=regex]
    [-via|proxy=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]
    [-sshOpts=ssh_options] [-timeout=n] [-out[=0|1] -olines=n -odir=path] [-et] [-v] [-d]
    <[username|remote_user@]host[,$via|proxy]> [<command>]

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-, ignored when using -via or Okta credentials)
     -p : Password or path to password file (default: undef)
     -sudo : Sudo to sudo_user and run <command> (default: root)
     -bg : Background mode (exit after sending command)
     -prompt : Shell prompt regex (default: '\][\$\#] $' )
     -via : Bastion host for Okta ASA sft client (default over -proxy)
     -proxy : Proxy host for ProxyJump (leave empty to enable over -via)
       -bu : Bastion user
       -ru : Remote user
             (default: Okta username -sft login-)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 s)
     -out : (Not defined) Display command output as it happens
            (0) Do not display command output
            (1) Buffer the output and display it after command completion (useful for concurrent execution)
     -olines : Display the last n lines of buffered output (default: 10 | full output: 0, implies -out=1)
     -odir : Directory in which the command output will be stored as a file (default: $PWD -current folder-)
     -et : Hide execution time
     -v : Enable verbose messages
     -d : Expect debugging	 
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     Encase <command> in quotes to pass it as a single argument
     Omit <command> for interactive mode
```
**scpexp.pl**
```
Usage: scpexp.pl [-help] [-version] [-u[=username]] [-p[=password]]
    [-via|proxy=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]
    [-sshOpts=ssh_options] [-timeout=n] [-tolocal] [-multiauth] [-q] [-r] [-et] [-v] [-d]
    <source_path> <[username|remote_user@]host[,$via|proxy]> [<target_path>]

     -help : Display usage
     -version : Display version information
     -u : Username (default: $USER -current user-, ignored when using -via or Okta credentials)
     -p : Password or path to password file (default: undef)
     -via : Bastion host for Okta ASA sft client (default over -proxy)
     -proxy : Proxy host for ProxyJump (leave empty to enable over -via)
       -bu : Bastion user
       -ru : Remote user
             (default: Okta username -sft login-)
     -sshOpts : Additional SSH options
                (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)
                Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
     -timeout : Timeout value for Expect (default: 20 s)
     -tolocal : Copy from remote host to local host (default: local -> remote)
                If permissions allow it, non-existent local directories in <target_path> will be created
     -multiauth : Always authenticate when password prompted (default: single authentication attempt)
     -q : Quiet mode disables the progress meter (default: enabled)
     -r : Recursively copy entire directories
     -et : Hide execution time
     -v : Enable verbose messages
     -d : Expect debugging
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     If omitted, <target_path> defaults to '.' (dot, or current directory) 
     Enable -multiauth along with -tolocal when <source_path> uses brace expansion
```

## How-To

(Assuming that `$SSH_USER` and `$SSH_PASS` have been set)

* Check the OS (RHEL) and kernel version on the remote hosts:

	`mdssh.pl -f=hosts 'cat /etc/redhat-release; uname -r'`

* Execute `df -h` and send the output to a file in the local `./df_output` directory:

	`mdssh.pl -f=hosts -odir=df_output 'df -h'`

* Push `package.rpm` to `/var/local/tmp` using 3 copy processes:

	`mdssh.pl -threads=3 -f=hosts -scp -target=/var/local/tmp package.rpm`

* Install (as root) the package, set timeout to 5 minutes:

	`mdssh.pl -timeout=300 -f=hosts -sudo 'rpm -ivh /var/local/tmp/package.rpm'`

* Delete the rpm file:

	`mdssh.pl -f=hosts 'rm /var/local/tmp/package.rpm'`

* Pull `/var/log/messages` to the local `./remote_files` directory:

	`mdssh.pl -f=hosts -scp -tolocal -target=remote_files /var/log/messages`
