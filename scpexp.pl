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

# SCP command-line utility with automatic authentication (no SSH keys required)
# Use -help for options

use strict;
use Expect;
use File::Basename;
use File::Path qw(make_path);

#$Expect::Exp_Internal = 1;
#$Expect::Debug = 1;

our ($help, $version, $u, $p, $sshOpts, $timeout, $tolocal, $r, $v, $multiauth, $q);

if ( $version ) {
	print "SCP command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 2.2\n";
	print "Release date: 06/01/2020\n";
	exit;
}

&usage if $help;
die "Required arguments: <source_path>, <host>\nUse -help for options\n" if @ARGV < 2;

my $timeout_default = 20;
$timeout = $timeout_default unless $timeout;
die "-timeout ($timeout) is not an integer" if $timeout =~ /\D/;

my ($spath, $host) = @ARGV;
my $tpath = $ARGV[2] || $ENV{HOME};

if ( $tolocal && !-e $tpath ) {
	my ($filename, $dir, $suffix) = fileparse $tpath;
	if ( -e $dir ) {
		die "Directory $dir is not writable\n" if !-w $dir;
	} else {
		print "Creating directory $dir...\n" if $v;
		unless( make_path $dir ) {
			die "Unable to create $dir: $!";
		}
	}
}

my $username = $u || $ENV{SSH_USER} || $ENV{USER};
my $password = $p || $ENV{SSH_PASS} || undef;
print "username = $username\n" if $v;

if ( defined $password ) {
	if ( -e $password ) {
		print "Password file $password found\n" if $v;
		$password = qx/cat $password/ or die;
		chomp($password);
	} else {
		print "Password file not found\n" if $v;
	}
} else {
	print "No password set\n" if $v;
}

# using -q (quiet mode) will make expect timeout for large files because the progress meter is disabled
my $scp = 'scp -C -o StrictHostKeyChecking=no -o CheckHostIP=no';
$scp .= " $sshOpts" if defined $sshOpts;
$scp .= " -r" if $r;
$scp .= ( $tolocal ? " $username\@$host:$spath $tpath" : " $spath $username\@$host:$tpath" );

my $exp = new Expect;
$exp->raw_pty(0);	# turn echoing (for sends) on=0 (default) / off=1
$exp->log_user(0);	# turn stdout logging on=1 (default) / off=0
#$exp->log_file("$0.log","a");	# log session to file: w=truncate / a=append (default)

if ( $v ) {
	print "Source path = $spath\n";
	print "Target path = $tpath\n";
	print "[$host] Executing scp (copy ";
	print $tolocal ? "to " : "from ";
	print "local)... ";
}

$exp->spawn($scp) or die $!;

my $pid = $exp->pid();
my $pw_sent = 0;
my $ret;

print "pid is [$pid]\n" if $v;

$exp->expect($timeout,
	[ '\(yes/no\)\?\s*$', 		sub { $exp->send("yes\n"); exp_continue } ],
	[ qr/password.*:\s*$/i, 	sub { &send_password(); exp_continue } ],
	[ qr/login:\s*$/i, 		sub { $exp->send("$username\n"); exp_continue } ],
	[ 'REMOTE HOST IDENTIFICATION HAS CHANGED', sub { print "[$host] Host key verification failed\n"; exp_continue } ],
	[ 'timeout', 			sub { die "[$host] Timeout" } ],
	# use \r (instead of \r\n) so there is a match to restart the timeout as the progress meter changes
	[ '\r', 			sub { my $output = $exp->before();
					$ret .= $output;
					print "[$host] $output\n" if ( !$q && $output =~ /(%|ETA)/ );
					exp_continue; } ],
);

$exp->soft_close();
$ret =~ s{^\Q$/\E}{}; # remove newline character from start of string

my $rc = ( $exp->exitstatus() >> 8 );
my $status_msg = 'OK';

if ( $rc ) {
	$status_msg = "Error (rc=$rc)\n$ret";
}

print "[$host] [$pid] -> $status_msg\n";
exit $rc;

# end of script

sub send_password {
	if ( defined $password ) {
		if ( $pw_sent == 0 ) {
			$pw_sent = 1;
			$exp->send("$password\n");
		} else {
			die "[$host] Wrong credentials"; }
	} else {
		die "[$host] Password required";
	}
}

sub usage {
	print "\nUsage: $0 [-help] [-version] [-u=username] [-p=password]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-tolocal] [-multiauth] [-r] [-v] [-q] <source_path> <host> [<target_path>]\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default seconds)\n";
	print "\t -tolocal : Copy from remote host to local host (default: local -> remote)\n";
	print "\t            If permissions allow it, non-existent local directories in <target_path> will be created\n";
	print "\t -multiauth : Always authenticate when password prompted (default: single authentication attempt)\n";
	print "\t -q : Quiet mode disables the progress meter (default: enabled)\n";
	print "\t -r : Recursively copy entire directories\n";
	print "\t -v : Enable verbose messages\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t If omitted, <target_path> default value is \$HOME\n";
	print "\t Enable -multiauth along with -tolocal when <source_path> uses brace expansion\n\n";
	exit;
}
