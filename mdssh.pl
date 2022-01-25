#!/usr/bin/perl -ws

# Copyright 2022 Mariano Dominguez
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Asynchronous parallel SSH/SCP command-line utility with automatic authentication (no SSH keys required)
# Use -help for options

use strict;
use File::Basename;
use POSIX qw/:sys_wait_h strftime/;
use Data::Dumper;
use File::Path qw(make_path);
use IO::Prompter;
use Time::HiRes qw( time usleep );

BEGIN { $| = 1 }

our ($help, $version, $u, $p, $prompt, $threads, $tcount, $ttime, $timeout, $scp, $r, $target, $tolocal, $multiauth, $meter, $sudo, $bg, $via, $proxy, $bu, $ru, $sshOpts, $s, $f, $v, $timestamp, $o, $olines, $odir, $minimal, $et);

$et = 1 if $minimal;

my $start = time() unless ( $et || $help || $version );
my $threads_default = 10;
my $tcount_default = 25;
my $ttime_default = 5;
my $timeout_default = 20;
my $olines_default = 10;
my $odir_default = $ENV{PWD};

if ( $version ) {
	print "Asyncronous parallel SSH/SCP command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 6.3\n";
	print "Release date: 2022-01-25\n";
	exit;
}

&usage if $help;
die "No hosts specified: Set -s or -f (or both)\nUse -help for options\n" unless ( $f || $s );
die "Missing argument: <command|source_path>\nUse -help for options\n" if @ARGV < 1;
die "Set either -via or -proxy\nUse -help for options\n" if ( $via && $proxy );

my $cmd_spath = $ARGV[0];
my (@hosts, @hosts_file, @hosts_cli);

if ( $f ) {
	my $hosts_file = $f;
	open my $fh, '<', $hosts_file or die "Can't open file $hosts_file: $!\n";
	@hosts_file = <$fh>;
	close $fh;
}

if ( $s ) {
	@hosts_cli = split " ", qx/echo $s/;
	# http://perldoc.perl.org/functions/split.html
	# any contiguous whitespace (not just a single space character) is used as a separator
	# equivalent to /\s+/ 
}

@hosts = (@hosts_file, @hosts_cli);
my $int_opts = {};
$int_opts->{'threads'} = $threads || $threads_default; # use default value if 0 or empty
$int_opts->{'tcount'} = $tcount // $tcount_default;
$int_opts->{'ttime'} = $ttime // $ttime_default;
$int_opts->{'timeout'} = $timeout || $timeout_default;

if ( not defined $o ) { 
	$int_opts->{'o'} = 1;
} elsif ( $o eq '1' ) {
	undef $o
} else {
	$int_opts->{'o'} = $o;
}

$int_opts->{'olines'} = $olines // $olines_default;
$int_opts->{'o'} = 1 if ( defined $olines );

foreach my $opt ( keys(%{$int_opts}) ) {
	die "-$opt ($int_opts->{$opt}) is not an integer\n" if $int_opts->{$opt} =~ /\D/;
}

if ( defined $odir ) {
	$odir = $odir_default if ( $odir eq '1' );
	if ( -e $odir ) {
		die "Directory $odir is not writable\n" if !-w $odir;
	} else {
		print "Creating directory $odir...\n" if $v;
		eval { make_path $odir }
			or die "Can't create directory $odir: $!\n";
	}
}

$v = 1 if $timestamp;

if ( $v ) {
	print "threads = $int_opts->{'threads'}\n";
	print "timeout = $int_opts->{'timeout'} s\n";
	print "o = $int_opts->{'o'}\n" if defined $int_opts->{'o'};
	print "olines = $int_opts->{'olines'}\n";
	print "odir = $odir\n" if defined $odir;
	print "SSH_USER = $ENV{SSH_USER}\n" if $ENV{SSH_USER};
	print "SSH_PASS is set\n" if $ENV{SSH_PASS};
	print "via = $via\n" if $via;
	print "proxy = $proxy\n" if $proxy;
	print "bu = $bu\n" if $bu;
	print "ru = $ru\n" if $ru;
	print "sshOpts = $sshOpts\n" if $sshOpts;
	print "Background mode enabled\n" if $bg;
}

if ( $u && $u eq '1' ) {
	$u = prompt "Username [$ENV{USER}]:", -in=>*STDIN, -timeout=>30, -default=>"$ENV{USER}";
	die "Timed out\n" if $u->timedout;
	print "Using default username\n" if $u->defaulted;
}
my $username = $u || $ENV{SSH_USER} || $ENV{USER};
print "username = $username\n" if $v;

if ( $p && $p eq '1' ) {
	$p = prompt 'Password:', -in=>*STDIN, -timeout=>30, -echo=>'';
	die "Timed out\n" if $p->timedout;
}
my $password = $p || $ENV{SSH_PASS} || undef;

if ( defined $password ) {
	if ( -e $password ) {
		print "Password file $password found\n" if $v;
		$password = qx/cat $password/ || die "Can't get password from file $password\n";
		chomp($password);
	} else {
		print "Password file not found\n" if $v;
	}
} else {
	print "No password set\n" if $v;
	$password = '';
}
$ENV{SSH_PASS} = $password;

my $sudo_user;
if ( $sudo && !$scp ) {
	$sudo_user = $sudo eq '1' ? 'root' : $sudo;
	print "Sudoing to user $sudo_user\n" if $v;
}

if ( $v ) {
	if ( $int_opts->{'tcount'} == 0 || $int_opts->{'ttime'} == 0 ) {
		print "Throttling is disabled\n";
	} else {
		print "tcount = $int_opts->{'tcount'}\nttime = $int_opts->{'ttime'} s\n";
	}
}

if ( $scp ) {
	$target = '.' if !$target;
	if ( $v ) {
		print "Executing SCP (copy ";
		print $tolocal ? "to " : "from ";
		print "local)\n";
		print "Source path: $cmd_spath\n";
		print "Target path: $target\n";
	}
}

print "-----\n" if $v;

my $hosts = {};
my $id = {};
my $forked_cnt = 0;
my $completed_cnt = 0;
my $running_cnt = 0;
my $error_hosts = {};
my @ok_hosts = ();
my $pid = $$;
my $num_hosts = 0;

foreach (@hosts) { ++$num_hosts unless ( /^\s*$/ || /(#+)/ ) }

my $throttle_cnt = 0;
my $throttle_flag = 0;
my $throttle_start;
my $ok_cnt = 0;
my $error_cnt = 0;
my $child_pid;

while ( $forked_cnt <= $#hosts ) {
	my $host = $hosts[$forked_cnt];
	chomp($host);
	next if $host =~ /(#+)/;
	next if $host =~ /^\s*$/;

	unless ( $throttle_flag ) {
		&fork_process($host, $via, $cmd_spath);
		++$throttle_cnt;
	} else {
		if ( $running_cnt != 0 ) {
			# Option 1: Set manual timer with random microsleep (less CPU intensive)
			usleep(rand(1000));
			$throttle_flag = 0 if ( &time() - $throttle_start > $int_opts->{'ttime'} ); 

			# Option 2: Set alarm and catch the SIGALRM signal
#			$SIG{ALRM} = sub {
#				$throttle_flag = 0;
#				print "Throttle timeout reached\n" if $v;
#			};
		} else {
			my $throttle_diff = $int_opts->{'ttime'} - (&time() - $throttle_start);
			print "No children running,";
			if ( $throttle_diff > 0 ) {
				printf(" sleeping %0.03f s\n", $throttle_diff);
				usleep($throttle_diff);
			} else {
				print " moving along\n";
			}
			$throttle_flag = 0;
		}
	}

	if ( $running_cnt > 0 ) {
		do { usleep(rand(250)); &check_process } until ( $running_cnt < $int_opts->{'threads'} || $child_pid == -1 );
	}

	if ( $throttle_cnt == $int_opts->{'tcount'} && $forked_cnt != $num_hosts && $int_opts->{'ttime'} != 0 ) {
		&log_trace("Throttling... forking in $int_opts->{'ttime'} s") if $v;
		$throttle_cnt = 0;
		$throttle_flag = 1;
		$throttle_start = time();
#		alarm $int_opts->{'ttime'};
	}
}

do { &check_process } until $child_pid == -1;

&log_trace("All processes completed") if $v;

my @sorted_ok_hosts = sort @ok_hosts;
#print Dumper $error_hosts;
print "-----\nNumber of hosts: $num_hosts\n~\n";
print "OK: $ok_cnt ";
print "| @sorted_ok_hosts" if $ok_cnt;

foreach my $rc ( sort { $a <=> $b } keys(%{$error_hosts}) ) {
	$error_cnt = scalar @{$error_hosts->{$rc}};
	print "\n~\n";
	print "Error (RC=$rc): $error_cnt ";

	if ( $error_cnt ) {
		my @sorted_error_hosts = sort @{$error_hosts->{$rc}};
		print "| @sorted_error_hosts";
	}
}

print "\n-----\n";
printf("Execution time: %0.03f s (aggregated)\n", &time() - $start) unless ( $et || $help || $version );

# End of script

sub log_trace {
	my $trace = "@_";
	if ( $timestamp ) {
		my $date = strftime "%m/%d/%Y at %H:%M:%S", localtime;
		$trace .= " _on_ $date";
	}
	print "$trace\n";
}

sub fork_process {
	my ($h, $via, $c) = @_;
	my $exit_code;
	my $host = $h;
	my $via_override;

	if ( $h =~ /(.+),([^\s].+[^\s])?/ ) {
		$host = $1;
		$via_override = $2 if $2;
	}

	$via = $proxy if $proxy;
	$via = $via_override if $via_override;

	my $p = fork();
	die "Fork failed: $!\n" unless defined $p;

	if ($p) {
		$hosts->{$p}->{'host'} = $host;
		$hosts->{$p}->{'via'} = $via if $via_override;
		$id->{$p} = ++$forked_cnt;
		++$running_cnt;
		my $log_msg = "[$host";
		$log_msg .= " __via__ $via" if ( $via && $via ne '1' );
		$log_msg .= "] [$p] process_$id->{$p} forked"; 
		&log_trace($log_msg) if $v;
		return $p;
	}

	my $dir = dirname($0);
	my $app = $scp ? "$dir/scpexp.pl" : "$dir/sshexp.pl";
	$app .= " -u=$username";
	$app .= " -via='$via'" if ( $via && !$proxy );
	$app .= " -proxy='$via'" if $proxy;
	$app .= " -bu=$bu" if $bu;
	$app .= " -ru=$ru" if $ru;
	$app .= " -sshOpts='$sshOpts'" if $sshOpts;
	$app .= " -timeout=$timeout" if $timeout;
	$app .= " -et" if $et;

	my $cmd;
	if ( $scp ) {
		$app .= " -r" if $r;
		$app .= " -q" unless $meter;
		if ( $tolocal ) {
			$app .= " -tolocal";
			$target .= "/$h/";
		}
		$app .= " -multiauth" if $multiauth;
		$cmd = "$app \"$c\" $host $target";
	} else {
		$app .= " -prompt=$prompt" if $prompt;
		$app .= " -sudo=$sudo_user" if $sudo;
		$app .= " -bg" if $bg;
		$app .= " -o=$int_opts->{'o'}" if defined $int_opts->{'o'};
		$app .= " -olines=$int_opts->{'olines'}" if defined $olines;
		$app .= " -odir=$odir" if defined $odir;
		$cmd = "$app $host \"$c\"";
	}
#	print "$cmd\n" if $v;
	system $cmd;

	$exit_code = $?>>8;
#	print "$exit_code\n";
	exit $exit_code;
}

sub check_process {
	$child_pid = waitpid(-1,&WNOHANG);
	if ($child_pid > 0) {
		++$completed_cnt;
		--$running_cnt;
		my $completed_percent = sprintf("%d%%", 100*$completed_cnt/$num_hosts);
		my $pending_cnt = $num_hosts-$completed_cnt;
		my $exit_code = $?>>8;
#		print "$child_pid exited with code " . ($exit_code) . "\n";

		my $host = $hosts->{$child_pid}->{'host'};
		$host .= ",$hosts->{$child_pid}->{'via'}" if $hosts->{$child_pid}->{'via'};

		if ( $? == 0 || ( $exit_code == 100 && $bg ) ) {
			push @ok_hosts, $host;
			++$ok_cnt;
		} else {
			push @{$error_hosts->{$exit_code}}, $host;
			++$error_cnt;
		}

		unless ( $v ) {
			unless ( $minimal ) {
				print "___ $completed_cnt/$num_hosts";
				printf(" in %0.03f s", &time() - $start) unless $et;
				print "\n";
			}
		} else {
			my $log_msg = "[$hosts->{$child_pid}->{'host'}";
			$log_msg .= " __via__ $hosts->{$child_pid}->{'via'}" if $hosts->{$child_pid}->{'via'};
			$log_msg .= "] [$child_pid] process_$id->{$child_pid} exited (Pending: $pending_cnt | Forked: $forked_cnt | $completed_cnt/$num_hosts -$completed_percent-";
			$log_msg .= sprintf(" in %0.03f s", &time() - $start) unless $et;
			$log_msg .= " | OK: $ok_cnt | Error: $error_cnt)";
			&log_trace($log_msg);
		}
	}
}

sub usage {
	print "\nUsage: $0 [-help] [-version] [-u[=username]] [-p[=password]]\n";
	print "\t[-sudo[=sudo_user]] [-bg] [-prompt=regex]\n";
	print "\t[-via|proxy=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-threads=n]\n";
	print "\t[-scp [-tolocal] [-multiauth] [-r] [-target=target_path] [-meter]]\n";
	print "\t[-tcount=throttle_count] [-ttime=throttle_time]\n";
	print "\t[-o[=0|1] -olines=n -odir=path] [-et] [-v [-timestamp]]\n";
	print "\t(-s=\"[user1@]host1[,\$via1|proxy1] [user2@]host2[,\$via2|proxy2] ...\" | -f=hosts_file) <command|source_path>\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-, ignored when using -via or Okta credentials)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sudo : Sudo to sudo_user and run <command> (default: root)\n";
	print "\t -bg : Background mode (exit after sending command)\n";
	print "\t -prompt : Shell prompt regex (default: '" . '\][\$\#] $' . "' )\n";
	print "\t -via : Bastion host for Okta ASA sft client (default over -proxy)\n";
	print "\t -proxy : Proxy host for ProxyJump (leave empty to enable over -via)\n";
	print "\t   -bu : Bastion user\n";
	print "\t   -ru : Remote user\n";
	print "\t         (default: Okta username -sft login-)\n"; 
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default s)\n";
	print "\t -threads : Number of concurrent processes (default: $threads_default)\n";
	print "\t -scp : Copy <source_path> from local host to \@remote_hosts:<target_path>\n";
	print "\t   -tolocal : Copy \@remote_hosts:<source_path> to <target_path> in local host\n";
	print "\t              The remote hostnames will be appended to <target_path> as a directory\n";
	print "\t              If permissions allow it, non-existent local directories will be created\n";
	print "\t   -multiauth : Always authenticate when password prompted (default: single authentication attempt)\n";
	print "\t   -r : Recursively copy entire directories\n";
	print "\t   -target : Target path (default: '.' -dot, or current directory-)\n";
	print "\t   -meter : Display scp progress (default: disabled)\n";
	print "\t -tcount : Number of forked processes before throttling (default: $tcount_default)\n";
	print "\t -ttime : Throttling time (default: $ttime_default s)\n";
	print "\t -o : (Not defined) Buffer the output and display it after command completion\n";
	print "\t      (0) Do not display command output\n";
	print "\t      (1) Display command output as it happens\n";
	print "\t -olines : Display the last n lines of buffered output (default: $olines_default | full output: 0, implies -o=0)\n";
	print "\t -odir : Local directory in which the command output will be stored as a file (default: \$PWD -current folder-)\n";
	print "\t         If permissions allow it, the directory will be created if it does not exit\n";
	print "\t -minimal : Hide process termination tracking in non-verbose mode (implies -et)\n";
	print "\t -et : Hide execution time\n";
	print "\t -v : Enable verbose messages\n";
	print "\t -timestamp : Display time (implies -v)\n";
	print "\t -s : Space-separated list of hostnames (brace expansion supported)\n";
	print "\t -f : File containing hostnames (one per line)\n";
	print "\t Set -tcount or -ttime to 0 to disable throttling\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t Enable -multiauth along with -tolocal when <source_path> uses brace expansion\n";
	print "\t Encase <command> in quotes (single argument)\n\n";
	exit;
}
