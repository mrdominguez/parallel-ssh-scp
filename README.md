# parallel-ssh
Asyncronous parallel ssh command-line utility.

Here is a preview of the available command options:
```
Usage: ./mdssh.pl [-u=username] [-p=password] [-sudo[=sudo_user]] [-timeout=n] [-threads=n]
	[-scp [-tolocal] [-multiauth] [-r] [-d=target_path] [-meter]] [-tcount=throttle_count] [-ttime=throttle_time]
	[-o[=0|1] -olines=n -odir=path] [-v [-timestamp]] (-s="host1 host2 ..." | -f=hosts_file) <command|source_path>

	 -u : Username (default: $USER -current user-)
	 -p : Password or path to password file (default: undef)
	 -sudo : Sudo to sudo_user and run <command> (default: root)
	 -timeout : Timeout value for Expect (default: 20 seconds)
	 -threads : Number of concurrent processes (default: 10)
	 -scp : Copy <source_path> from local host to @remote_hosts:<target_path>
	 -tolocal : Copy @remote_hosts:<source_path> to <target_path> in local host
	            The remote hosts' hostname will be added before the file or the last directory in <target_path>
	            If permissions allow it, non-existant local directories will be created
	 -multiauth : Always authenticate when password prompted (default: single authentication attempt)
	 -r : Recursively copy entire directories
	 -d : Remote path (default: $HOME)
	 -meter : Display scp progress (default: disabled)
	 -tcount : Number of forked processes before throttling (default: 25)
	 -ttime : Throttling time (default: 3 seconds)
	 -o : (Not defined) Buffer output and display after command completion
	      (0) Do not display command output
	      (1) Display command output as it happens
	 -olines : Display the last n lines of the buffered output (-o=1 -> default: 10 | full output: 0)
	 -odir : Local directory in which the command output will be stored as a file (default: current folder)
	         If permissions allow it, the directory will be created if it does not exit
	 -v : Enable verbose messages / progress information
	 -timestamp : Display timestamp
	 -s : Space-separated list of hostnames (brace expansion supported)
	 -f : File containing hostnames (one per line)
	 Set tcount or ttime to 0 to disable throttling
	 Use envoriment variables $SSH_USER and $SSH_PASS to pass credentials
	 Enable -multiauth along with -tolocal when <source_path> uses brace expasion
	 Encase <command> in quotes (single argument)
```
