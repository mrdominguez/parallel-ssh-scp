#!/usr/bin/perl -ws

# Copyright 2020 Mariano Dominguez
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

BEGIN { $| = 1 }

our ($help, $version, $u, $p, $sshOpts, $threads, $tcount, $ttime, $timeout, $scp, $r, $d, $tolocal, $multiauth, $meter, $sudo, $s, $f, $v, $timestamp, $o, $olines, $odir);
my $threads_default = 10;
my $tcount_default = 25;
my $ttime_default = 5;
my $timeout_default = 20;
my $olines_default = 10;
my $odir_default = $ENV{PWD};

if ( $version ) {
	print "Asyncronous parallel SSH/SCP command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 3.2\n";
	print "Release date: 2020-08-22\n";
	exit;
}

&usage if $help;
die "No hosts specified: Set -s or -f (or both)\nUse -help for options\n" unless ( $f || $s );
die "Missing argument: <command|source_path>\nUse -help for options\n" if @ARGV < 1;

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

if ( $v ) {
	print "threads = $int_opts->{'threads'}\n";
	print "timeout = $int_opts->{'timeout'} seconds\n";
	print "o = $int_opts->{'o'}\n" if defined $int_opts->{'o'};
	print "olines = $int_opts->{'olines'}\n";
	print "odir = $odir\n" if defined $odir;
}

if ( $u && $u eq '1' ) {
	$u = prompt "Username [$ENV{USER}]:", -in=>*STDIN, -timeout=>30, -default=>"$ENV{USER}";
	die "Timed out\n" if $u->timedout;
	print "Using default username\n" if $u->defaulted;
}

if ( $p && $p eq '1' ) {
	$p = prompt 'Password:', -in=>*STDIN, -timeout=>30, -echo=>'';
	die "Timed out\n" if $p->timedout;
}

if ( $v ) {
	print "SSH_USER = $ENV{SSH_USER}\n" if $ENV{SSH_USER};
	print "SSH_PASS is set\n" if $ENV{SSH_PASS};
}

my $username = $u || $ENV{SSH_USER} || $ENV{USER};
my $password = $p || $ENV{SSH_PASS} || undef;
print "username = $username\n" if $v;

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
		print "tcount = $int_opts->{'tcount'}\nttime = $int_opts->{'ttime'} seconds\n";
	}
}

if ( $scp ) {
	$d = $ENV{HOME} if !$d;
	if ( $v ) {
		print "Executing SCP (copy ";
		print $tolocal ? "to " : "from ";
		print "local)\n";
		print "Source path: $cmd_spath\n";
		print "Target path: $d\n";
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
my $ok_cnt = 0;
my $error_cnt = 0;
my $child_pid;

foreach my $host (@hosts) {
	chomp($host);
	next if $host =~ /(#+)/;
	next if $host =~ /^\s*$/;
	++$throttle_cnt;
	&fork_process($host, $cmd_spath);
	if ( $running_cnt >= $int_opts->{'threads'} ) {
		do { &check_process } until ( $running_cnt < $int_opts->{'threads'} || $child_pid == -1 );	
	}
	if ( $throttle_cnt == $int_opts->{'tcount'} && $forked_cnt != $num_hosts && $int_opts->{'ttime'} != 0 ) {
		&log_trace ("Throttling... resuming in $int_opts->{'ttime'} seconds");
		sleep $int_opts->{'ttime'};
		$throttle_cnt = 0;
	}
}

do { &check_process } until $child_pid == -1;

&log_trace ("All processes completed");

my @sorted_ok_hosts = sort @ok_hosts;
#print Dumper $error_hosts;
print "-----\nNumber of hosts: $num_hosts\n~\n";
print "OK: $ok_cnt ";
print "| @sorted_ok_hosts" if $ok_cnt;

foreach my $rc ( sort { $a <=> $b } keys(%{$error_hosts}) ) {
	$error_cnt = scalar @{$error_hosts->{$rc}};
	print "\n~\n";
	print "Error (rc=$rc): $error_cnt ";
	if ( $error_cnt ) {
		my @sorted_error_hosts = sort @{$error_hosts->{$rc}};
		print "| @sorted_error_hosts";
	}
}

print "\n";

sub log_trace {
	my $date = strftime "%m/%d/%Y %H:%M:%S", localtime;
	my $trace = "@_";
	$trace .= " ... [$date]" if $v && $timestamp;
	print "$trace\n" if $v;
}

sub fork_process {
	my ($h, $c) = @_;
	my $exit_code;
	my $p = fork();
	die "Fork failed: $!\n" unless defined $p;

	if ($p) {
		$hosts->{$p} = $h;
		$id->{$p} = ++$forked_cnt;
		++$running_cnt;
		&log_trace ("[$h] [$p] process_$id->{$p} forked");
		return $p;
	}

	my $dir = dirname($0);
	my $app = $scp ? "$dir/scpexp.pl" : "$dir/sshexp.pl";
	$app .= " -u=$username";
	$app .= " -sshOpts='$sshOpts'" if defined $sshOpts;
	$app .= " -timeout=$timeout" if $timeout;
		
	if ( $scp ) {
		$app .= " -r" if $r;
		$app .= " -q" unless $meter;
		if ( $tolocal ) {
			$app .= " -tolocal";
			$d .= "/$h/";
		}
		$app .= " -multiauth" if $multiauth;
		system("$app \"$c\" $h $d");
	} else {
		$app .= " -sudo=$sudo_user" if $sudo;
		$app .= " -o=$int_opts->{'o'}" if defined $int_opts->{'o'};
		$app .= " -olines=$int_opts->{'olines'}" if defined $olines;
		$app .= " -odir=$odir" if defined $odir;
		system("$app $h \"$c\"");
	}

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
#		print "$child_pid exited with code " . ($?>>8) . "\n";
		if ( $? == 0 ) {
			push @ok_hosts, $hosts->{$child_pid};
			++$ok_cnt;
		} else {
			push @{$error_hosts->{$?>>8}}, $hosts->{$child_pid};
			++$error_cnt;
		}
		&log_trace ("[$hosts->{$child_pid}] [$child_pid] process_$id->{$child_pid} exited (Pending: $pending_cnt | Forked: $forked_cnt | Completed: $completed_cnt/$num_hosts -$completed_percent- | OK: $ok_cnt | Error: $error_cnt)");
	}
}

sub usage {
	print "\nUsage: $0 [-help] [-version] [-u[=username]] [-p[=password]]\n";
	print "\t[-sudo[=sudo_user]] [-sshOpts=ssh_options] [-timeout=n] [-threads=n]\n";
	print "\t[-scp [-tolocal] [-multiauth] [-r] [-d=target_path] [-meter]]\n";
	print "\t[-tcount=throttle_count] [-ttime=throttle_time]\n";
	print "\t[-o[=0|1] -olines=n -odir=path] [-v [-timestamp]] (-s=\"host1 host2 ...\" | -f=hosts_file) <command|source_path>\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sudo : Sudo to sudo_user and run <command> (default: root)\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default seconds)\n";
	print "\t -threads : Number of concurrent processes (default: $threads_default)\n";
	print "\t -scp : Copy <source_path> from local host to \@remote_hosts:<target_path>\n";
	print "\t -tolocal : Copy \@remote_hosts:<source_path> to <target_path> in local host\n";
	print "\t            The remote hostnames will be appended to <target_path> as a directory\n";
	print "\t            If permissions allow it, non-existent local directories will be created\n";
	print "\t -multiauth : Always authenticate when password prompted (default: single authentication attempt)\n";
	print "\t -r : Recursively copy entire directories\n";
	print "\t -d : Target path (default: \$HOME)\n";
	print "\t -meter : Display scp progress (default: disabled)\n";
	print "\t -tcount : Number of forked processes before throttling (default: $tcount_default)\n";
	print "\t -ttime : Throttling time (default: $ttime_default seconds)\n";
	print "\t -o : (Not defined) Buffer the output and display it after command completion\n";
	print "\t      (0) Do not display command output\n";
	print "\t      (1) Display command output as it happens\n";
	print "\t -olines : Ignore -o and display the last n lines of buffered output (default: $olines_default | full output: 0)\n";
	print "\t -odir : Local directory in which the command output will be stored as a file (default: \$PWD -current folder-)\n";
	print "\t         If permissions allow it, the directory will be created if it does not exit\n";
	print "\t -v : Enable verbose messages / progress information\n";
	print "\t -timestamp : Display timestamp\n";
	print "\t -s : Space-separated list of hostnames (brace expansion supported)\n";
	print "\t -f : File containing hostnames (one per line)\n";
	print "\t Set -tcount or -ttime to 0 to disable throttling\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t Enable -multiauth along with -tolocal when <source_path> uses brace expansion\n";
	print "\t Encase <command> in quotes (single argument)\n\n";
	exit;
}
