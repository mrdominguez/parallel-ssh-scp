#!/usr/bin/perl -ws

# Copyright 2023 Mariano Dominguez
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

# SCP command-line utility with automatic authentication (no SSH keys required)
# Use -help for options

use strict;
use Expect;
use File::Basename;
use File::Path qw(make_path);
use IO::Prompter;
use Time::HiRes qw( time );

our ($help, $version, $u, $p, $via, $proxy, $bu, $ru, $sshOpts, $timeout, $tolocal, $r, $et, $v, $multiauth, $q, $d);

my $start = time() unless ( $et || $help || $version );

if ( $d ) {
	$Expect::Exp_Internal = 1;	# Set/unset 'exp_internal' debugging
	$Expect::Debug = 1;		# Object debugging
}

if ( $version ) {
	print "SCP command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 6.7.5\n";
	print "Release date: 2023-10-24\n";
	exit;
}

my $timeout_default = 20;
my $pid = 0;

&usage if $help;
die "Required arguments: <source_path>, <host>\nUse -help for options\n" if @ARGV < 2;
die "Set either -via or -proxy\nUse -help for options\n" if ( $via && $proxy );

$timeout = $timeout_default unless $timeout;
die "-timeout ($timeout) is not an integer\n" if $timeout =~ /\D/;

my ($spath, $host) = @ARGV;
my $tpath = $ARGV[2] || '.';

if ( $host =~ /(.+),([^\s].+[^\s])?/ ) {
	$host = $1;
	if ( $2 ) { $proxy ? $proxy = $2 : $via = $2 }
}

if ( $host =~ /(.+)\@(.+)/ ) {
	$host = $2;
	( $proxy || $via ) ? $ru = $1 : $u = $1
}

if ( $tolocal && !-e $tpath ) {
	my ($filename, $dir, $suffix) = fileparse $tpath;
	if ( -e $dir ) {
		die "Directory $dir is not writable\n" if !-w $dir;
	} else {
		print "Creating directory $dir...\n" if $v;
		eval { make_path $dir }
			or die "Can't create directory $dir: $!\n";
	}
}

if ( $v ) {
	print "timeout = ${timeout}s\n";
	print "SSH_USER = $ENV{SSH_USER}\n" if $ENV{SSH_USER};
	print "SSH_PASS is set\n" if $ENV{SSH_PASS};
	print "via = $via\n" if $via;
	print "proxy = $proxy\n" if $proxy;
	print "bu = $bu\n" if $bu;
	print "ru = $ru\n" if $ru;
	print "sshOpts = $sshOpts\n" if $sshOpts;
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
}

# Using -q (quiet mode) will make expect timeout for large files because the progress meter is disabled
my $scp = 'scp -C -o StrictHostKeyChecking=no -o CheckHostIP=no';
if ( $via && $via ne '1' ) {
	$via = "$bu\@$via" if ( $via !~ /\@/ && $bu );
	$scp .= " -o UserKnownHostsFile=/dev/null -o 'ProxyCommand sft proxycommand --via $via ";
	$scp .= "$ru\@" if $ru;
	$scp .= "$host'";
} elsif ( $proxy && $proxy ne '1' ) {
	if ( $proxy !~ /\@/ ) { $proxy = ( $bu ? $bu : $username ) . "\@$proxy" }
	$scp .= " -J $proxy";
	$username = $ru if $ru
}
$scp .= " $sshOpts" if $sshOpts;
$scp .= " -r" if $r;
# $username below gets ignored when using $via (with or without $ru), what matters is the ProxyCommand
$scp .= ( $tolocal ? " $username\@$host:$spath $tpath" : " $spath $username\@$host:$tpath" );
print "$scp\n" if $v;

my $exp = new Expect;
$exp->raw_pty(0);
$exp->log_stdout(0);		# Set (1) -default-, unset (0) logging to STDOUT
#$exp->log_file("$0.log","a");	# Log session to file (a=append -default-, w=truncate)

if ( $v ) {
	print "source_path = $spath\n";
	print "target_path = $tpath\n";
	print "[$host] Executing SCP (copy ";
	print $tolocal ? "to " : "from ";
	print "local)... ";
}

$exp->spawn($scp) or die "Cannot spawn scp: $!\n";
$pid = $exp->pid();
print "PID: $pid\n" if $v;

my $pw_sent = 0;
my $ret;
$exp->expect($timeout,
          # Are you sure you want to continue connecting (yes/no/[fingerprint])?
	[ '\(yes/no(/.*)?\)\?\s*$',		sub {
						  print "The authenticity of host \'$host\' can't be established\n" if $v;
		  				  &send_yes() } ],
	[ qr/password.*:\s*$/i,			sub { &send_password() } ],
	[ qr/login:\s*$/i,			sub { $exp->send("$username\n"); exp_continue } ],
	[ 'Host key verification failed',	sub { die "[$host] (auth) Host key verification failed\n" } ],
	[ qr/Add to known_hosts\?.*/i,		sub { &send_yes() } ],
	  # Expect TIMEOUT
	[ 'timeout',				sub { die "[$host] Timeout\n" } ],
	  # Use \r (instead of \r\n) so there is a match to restart the timeout as the progress meter changes
	[ '\r',					sub {
						  my $output = $exp->before();
						  $ret .= $output;
						  print "[$host] $output\n" if ( !$q && $output =~ /(%|ETA)/ );
						  exp_continue; } ],
);
$exp->soft_close();
$ret =~ s{^\Q$/\E}{};		# Remove newline character from start of string

my $rc = ( $exp->exitstatus() >> 8 );
my $msg_status = $rc ? "Error (RC=$rc)\n$ret" : 'OK';

print "[$host] [$pid] -> $msg_status\n";
exit $rc;

END {
	print "[$host] [$pid] Execution time - " . &parse_duration(&time() - $start) . "\n" unless ( $et || $help || $version || !$host );
}

# End of script

sub parse_duration {
	use integer;
	my $duration = sprintf("%.3f", shift);
	my $hours = $duration/3600;
	my $minutes = $duration%3600/60;
	my $seconds = $duration%60;
	my ($milliseconds) = $duration =~ m/\.(.*)/;

	my $formatted_duration;
	$formatted_duration = sprintf("%.3fs", $duration) if ( $hours == 0 && $minutes == 0 );
	$formatted_duration = sprintf("%dm:%02d.%ss", $minutes, $seconds, $milliseconds) if ( $hours == 0 && $minutes > 0 );
	$formatted_duration = sprintf("%dh:%02dm:%02d.%ss", $hours, $minutes, $seconds, $milliseconds) if $hours > 0;
	return $formatted_duration;
}

sub send_password {
	if ( defined $password ) {
		if ( $pw_sent == 0 ) {
			$exp->send("$password\n");
			$pw_sent = 1 unless $multiauth;
		} else {
			die "[$host] Wrong credentials\n"; }
	} else {
		die "[$host] Password required\n";
	}
	exp_continue;
}

sub send_yes {
	$exp->slave->stty(qw(-echo));
	$exp->send("yes\n");
	$exp->slave->stty(qw(echo));
	exp_continue;
}

sub usage {
	print "\nUsage: $0 [-help] [-version] [-u[=username]] [-p[=password]]\n";
	print "\t[-via|proxy=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-tolocal] [-multiauth] [-q] [-r] [-et] [-v] [-d]\n";
	print "\t<source_path> <[username|remote_user@]host[,\$via|proxy]> [<target_path>]\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-, ignored when using Okta credentials -sft login-)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -via : Bastion host for Okta ASA sft client (default over -proxy)\n";
	print "\t -proxy : Proxy host for ProxyJump (leave empty to enable over -via)\n";
	print "\t   -bu : Bastion user\n";
	print "\t   -ru : Remote user\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no -o UserKnownHostsFile=/dev/null)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: ${timeout_default}s)\n";
	print "\t -tolocal : Copy from remote host to local host (default: local -> remote)\n";
	print "\t            If permissions allow it, non-existent local directories in <target_path> will be created\n";
	print "\t -multiauth : Always authenticate when password prompted (default: single authentication attempt)\n";
	print "\t -q : Quiet mode disables the progress meter (default: enabled)\n";
	print "\t -r : Recursively copy entire directories\n";
	print "\t -et : Hide execution time\n";
	print "\t -v : Enable verbose messages\n";
	print "\t -d : Expect debugging\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t If omitted, <target_path> defaults to '.' (dot, or current directory)\n";
	print "\t Enable -multiauth along with -tolocal when <source_path> uses brace expansion\n\n";
	exit;
}
