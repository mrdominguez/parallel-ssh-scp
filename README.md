## Synopsis

AUTHOR: Mariano Dominguez, <marianodominguez@hotmail.com>

VERSION: 2.2

FEEDBACK/BUGS: Please contact me by email.

`mdssh.pl` (as in my initials, MD) is an asynchronous parallel SSH/SCP command-line utility that does not require setting up SSH keys. It enables process concurrency and calls `sshexp.pl` and `scpexp.pl` in the background to connect to remote hosts (one host per process) via `ssh` or `scp` respectively.

Sudo operations that require password input are also supported (`-sudo`).

## Sample Output

Check the status of the *ntpd* service on *node1*, *node2*, *node3* and *cdsw*:
```
MacBook-Pro:~ mdominguez$ mdssh.pl -s="node{1..3} cdsw" 'service ntpd status'
[node1] [13328] -> OK
Jun 01 14:34:28 node1.localdomain ntpd[8186]: 0.0.0.0 c012 02 freq_set kernel -0.581 PPM
Jun 01 14:34:28 node1.localdomain ntpd[8206]: signal_no_reset: signal 17 had flags 4000000
Jun 01 14:34:34 node1.localdomain ntpd[8186]: Listen normally on 4 eno16777736 192.168.0.191 UDP 123
Jun 01 14:34:34 node1.localdomain ntpd[8186]: Listen normally on 5 eno16777736 fe80::20c:29ff:fea9:865e UDP 123
Jun 01 14:34:34 node1.localdomain ntpd[8186]: new interface(s) found: waking up resolver
Jun 01 14:34:36 node1.localdomain ntpd_intres[8206]: DNS 0.centos.pool.ntp.org -> 66.228.48.38
Jun 01 14:34:36 node1.localdomain ntpd_intres[8206]: DNS 1.centos.pool.ntp.org -> 184.105.182.7
Jun 01 14:34:36 node1.localdomain ntpd_intres[8206]: DNS 2.centos.pool.ntp.org -> 72.87.88.203
Jun 01 14:34:36 node1.localdomain ntpd_intres[8206]: DNS 3.centos.pool.ntp.org -> 206.55.191.142
Jun 01 14:34:43 node1.localdomain ntpd[8186]: 0.0.0.0 c615 05 clock_sync
[node3] [13327] -> Error (rc=3)
Jun 01 15:13:31 node3.localdomain ntpd_intres[8189]: DNS 0.centos.pool.ntp.org -> 129.250.35.251
Jun 01 15:13:31 node3.localdomain ntpd_intres[8189]: DNS 1.centos.pool.ntp.org -> 65.19.178.219
Jun 01 15:13:31 node3.localdomain ntpd_intres[8189]: DNS 2.centos.pool.ntp.org -> 174.143.130.91
Jun 01 15:13:31 node3.localdomain ntpd_intres[8189]: DNS 3.centos.pool.ntp.org -> 38.229.71.1
Jun 01 15:13:32 node3.localdomain ntpd[8177]: Listen normally on 5 eno16777736 fe80::250:56ff:fe22:80cb UDP 123
Jun 01 15:13:32 node3.localdomain ntpd[8177]: new interface(s) found: waking up resolver
Jun 01 15:13:37 node3.localdomain ntpd[8177]: 0.0.0.0 c615 05 clock_sync
Jun 01 15:24:34 node3.localdomain ntpd[8177]: ntpd exiting on signal 15
Jun 01 15:24:34 node3.localdomain systemd[1]: Stopping Network Time Service...
Jun 01 15:24:34 node3.localdomain systemd[1]: Stopped Network Time Service.
[cdsw] [13330] -> OK
Jun 01 15:13:32 cdsw-cdh.cdhdomain ntpd[956]: 0.0.0.0 c012 02 freq_set kernel -2.508 PPM
Jun 01 15:13:32 cdsw-cdh.cdhdomain ntpd[960]: signal_no_reset: signal 17 had flags 4000000
Jun 01 15:13:34 cdsw-cdh.cdhdomain ntpd_intres[960]: DNS 0.centos.pool.ntp.org -> 45.33.2.219
Jun 01 15:13:34 cdsw-cdh.cdhdomain ntpd_intres[960]: DNS 1.centos.pool.ntp.org -> 172.98.193.44
Jun 01 15:13:34 cdsw-cdh.cdhdomain ntpd_intres[960]: DNS 2.centos.pool.ntp.org -> 174.143.130.91
Jun 01 15:13:34 cdsw-cdh.cdhdomain ntpd_intres[960]: DNS 3.centos.pool.ntp.org -> 216.126.233.109
Jun 01 15:13:35 cdsw-cdh.cdhdomain ntpd[956]: Listen normally on 4 eno16777736 192.168.0.203 UDP 123
Jun 01 15:13:35 cdsw-cdh.cdhdomain ntpd[956]: Listen normally on 5 eno16777736 fe80::20c:29ff:fee3:13c3 UDP 123
Jun 01 15:13:35 cdsw-cdh.cdhdomain ntpd[956]: new interface(s) found: waking up resolver
Jun 01 15:13:42 cdsw-cdh.cdhdomain ntpd[956]: 0.0.0.0 c615 05 clock_sync
ssh: connect to host node2 port 22: No route to host
[node2] (auth) Premature EOF
-----
Number of hosts: 4
~
OK: 2 | cdsw node1
~
Error (rc=3): 1 | node3
~
Error (rc=255): 1 | node2
MacBook-Pro:~ mdominguez$
```

Restart the *ntpd* service and use verbose output (`-v`), which is especially helpful to track progress when managing hundreds of hosts:
```
MacBook-Pro:~ mdominguez$ mdssh.pl -v -sudo -s="node{1..3} cdsw" 'service ntpd restart'
threads = 10
timeout = 20 seconds
o = 1
olines = 10
username = mdominguez
Password file /Users/mdominguez/ssh_password found
Sudoing to user root
tcount = 25
ttime = 5 seconds
-----
[node1] [13397] process_1 forked
[node2] [13398] process_2 forked
[node3] [13400] process_3 forked
[cdsw] [13402] process_4 forked
[node3] [13408] -> OK
Redirecting to /bin/systemctl restart  ntpd.service
[node3] [13400] process_3 exited (Pending: 3 | Forked: 4 | Completed: 1/4 -25%- | OK: 1 | Error: 0)
[node1] [13405] -> OK
Redirecting to /bin/systemctl restart  ntpd.service
[node1] [13397] process_1 exited (Pending: 2 | Forked: 4 | Completed: 2/4 -50%- | OK: 2 | Error: 0)
[cdsw] [13407] -> OK
Redirecting to /bin/systemctl restart  ntpd.service
[cdsw] [13402] process_4 exited (Pending: 1 | Forked: 4 | Completed: 3/4 -75%- | OK: 3 | Error: 0)
ssh: connect to host node2 port 22: No route to host
[node2] (auth) Premature EOF
[node2] [13398] process_2 exited (Pending: 0 | Forked: 4 | Completed: 4/4 -100%- | OK: 3 | Error: 1)
All processes completed
-----
Number of hosts: 4
~
OK: 3 | cdsw node1 node3
~
Error (rc=255): 1 | node2
MacBook-Pro:~ mdominguez$
```

## Installation

These utilities are written in Perl and have been tested using *Perl 5.1x.x* on *RHEL 6/7*, as well as *macOS Sierra* and after.

Authentication and credentials are handled using the **Expect.pm** module. The interactive mode functionality in `sshexp.pl` requires **IO::Stty**.

Use [cpan](http://perldoc.perl.org/cpan.html) to install the aforementioned modules; alternately, download them from the [CPAN Search Site](http://search.cpan.org/) for manual installation.

**IMPORTANT: Set the `$shell_prompt` variable in `sshexp.pl` to a regex matching the end of `$PS1` (prompt shell variable) for Expect to correctly catch command execution termination as the default value `'\][\$\#] $'` may not always work**.

## Setting Credentials

The username can be set by using the `-u` option in the command line or the `$SSH_USER` environment variable. If not set, the default username is `$USER`.

The password can be passed by setting the `-p` option or the `$SSH_PASS` environment variable to:
- The actual password string (**not recommended**).
- A file containing the password.

If not set, the password will be undefined.

## Usage

**mdssh.pl**
```
Usage: mdssh.pl [-help] [-version] [-u=username] [-p=password]
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
     -o : (Not defined) Buffer output; display it after command completion
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
- Unless overridden by the SSH **ConnectTimeout** option, the system's TCP connect timeout value will be used (the default for Linux is 20 seconds). To change it, set `-sshOpts` as follows  `-sshOpts='-o ConnectTimeout=10'` (in seconds).
- Both `-f` and `-s` can be used at the same time.
- Lines containing the `#` character in the hosts file will be skipped.

**sshexp.pl**
```
Usage: sshexp.pl [-help] [-version] [-u=username] [-p=password] [-sudo[=sudo_user]]
    [-sshOpts=ssh_options] [-timeout=n] [-o[=0|1] -olines=n -odir=path] [-v] <host> [<command>]

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
          (1) Buffer output; display it after command completion (useful for concurrent execution)
     -olines : Ignore -o and display the last n lines of buffered output (default: 10 | full output: 0)
     -odir : Directory in which the command output will be stored as a file (default: $PWD -current folder-)
     -v : Enable verbose messages
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     Encase <command> in quotes to pass it as a single argument
     Omit <command> for interactive mode
```
**scpexp.pl**
```
Usage: scpexp.pl [-help] [-version] [-u=username] [-p=password]
    [-sshOpts=ssh_options] [-timeout=n] [-tolocal] [-multiauth] [-r] [-v] [-q] <source_path> <host> [<target_path>]

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
     Use environment variables $SSH_USER and $SSH_PASS to pass credentials
     If omitted, <target_path> default value is $HOME
     Enable -multiauth along with -tolocal when <source_path> uses brace expansion
```

## How-To

(Assuming `$SSH_USER` and `$SSH_PASS` have been set)

* Check the OS (RHEL) and kernel version on the remote hosts:

	`$ mdssh.pl -f=hosts 'cat /etc/redhat-release; uname -r'`

* Execute `df -h` and send the output to a file in the local `./df_output` directory:

	`$ mdssh.pl -f=hosts -odir=df_output 'df -h'`

* Push `package.rpm` to `/var/local/tmp` using 3 copy processes:

	`$ mdssh.pl -threads=3 -f=hosts -scp -d=/var/local/tmp package.rpm`

* Install (as root) the package, set timeout to 5 minutes:

	`$ mdssh.pl -timeout=300 -f=hosts -sudo 'rpm -ivh /var/local/tmp/package.rpm'`

* Delete the rpm file:

	`$ mdssh.pl -f=hosts 'rm /var/local/tmp/package.rpm'`

* Pull `/var/log/messages` to the local `./remote_files` directory:

	`$ mdssh.pl -f=hosts -scp -tolocal -d=remote_files /var/log/messages`
