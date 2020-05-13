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

# SSH command-line utility with automatic authentication (no SSH keys required)
# Use -help for options

use strict;
use Expect;
use File::Basename;

#$Expect::Exp_Internal = 1;
#$Expect::Debug = 1;

our ($help, $version, $u, $p, $sshOpts, $sudo, $timeout, $o, $olines, $odir, $v);
my $timeout_default = 20;
my $olines_default = 10;
my $odir_default = $ENV{PWD};

if ( $version ) {
	print "SSH command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 2.1\n";
	print "Release date: 05/12/2020\n";
	exit;
}

&usage if $help;
die "Missing agument: <host>\nUse -help for options\n" if @ARGV < 1;

my $int_opts = {};
$int_opts->{'timeout'} = $timeout || $timeout_default; # use default value if 0 (or empty)
if ( defined $olines ) {
	$int_opts->{'o'} = 1;
} elsif ( defined $o ) {
	$int_opts->{'o'} = $o;
}
$int_opts->{'olines'} = $olines // $olines_default;
$odir = $odir_default if ( defined $odir && $odir eq '1' );

foreach my $opt ( keys(%{$int_opts}) ) {
	die "-$opt ($int_opts->{$opt}) is not an integer" if $int_opts->{$opt} =~ /\D/;
}

if ( $v ) {
	print "timeout = $int_opts->{'timeout'} seconds\n";
	print "o = $int_opts->{'o'}\n" if defined $int_opts->{'o'};
	print "olines = $int_opts->{'olines'}\n";
	print "odir = $odir\n" if defined $odir;
}

my ($host, $cmd) = @ARGV;
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

my $ssh = 'ssh -o StrictHostKeyChecking=no -o CheckHostIP=no';
$ssh .= " $sshOpts" if defined $sshOpts;
$ssh .= " $username\@$host";
#my $shell_prompt = qr'[\~\$\>\#]\s$';
# \s will match newline, use literal space instead
my $shell_prompt = qr'\][\$\#] $';

my $exp = new Expect;
$exp->raw_pty(0);	# turn echoing (for sends) on=0 (default) / off=1
$exp->log_user(0);	# turn stdout logging on=1 (default) / off=0
print "[$host] Executing ssh... " if $v;
$exp->spawn($ssh) or die $!;
my $pid = $exp->pid();
print "pid is [$pid]\n" if $v;
#$exp->log_file("$0.log","a"); 	# log session to file: w=truncate / a=append (default)
my $pw_sent = 0;
$exp->expect($int_opts->{'timeout'},
	# The authenticity of host '' can't be established... to continue connecting (yes/no)?
	[ '\(yes/no\)\?\s*$', 		sub { $exp->send("yes\n"); exp_continue } ],
	[ qr/password.*:\s*$/i, 	sub { &send_password(); exp_continue } ],
	[ qr/login:\s*$/i, 		sub { $exp->send("$username\n"); exp_continue } ],
	[ 'REMOTE HOST IDENTIFICATION HAS CHANGED', sub { print "[$host] Host key verification failed\n"; exp_continue } ],
	[ 'eof', 			sub { &no_match("[$host] (auth) Premature EOF") } ],
	# Expect TIMEOUT
	[ 'timeout', 			sub { die "[$host] (auth) Timeout" } ], 
	[ $shell_prompt ],
);

if ( $sudo ) {
	$pw_sent = 0;
	my $sudo_cmd;
	my $sudo_user = $sudo eq '1' ? 'root' : $sudo;
	print "[$host] Executing command through sudo as user $sudo_user\n" if $v;
	$sudo_cmd = "sudo su - $sudo_user\n"; # Option 1
#	$sudo_cmd = "sudo -i -u $sudo_user\n"; # Option 2
	$exp->send("$sudo_cmd");
	$exp->expect($int_opts->{'timeout'},
#		[ qr/password.*:\s*$/i, 	sub { $exp->send("$password\n"); exp_continue } ],
		# if $password is undefined and ssh does not require it, sudo may still prompt for password...
		[ qr/password.*:\s*$/i, 	sub { &send_password(); exp_continue } ],
		[ 'unknown', 			sub { die "[$host] Unknown user: $sudo_user" } ],
		[ 'does not exist', 		sub { die "[$host] User does not exist: $sudo_user" } ],
		[ 'not allowed to execute', 	sub { die "[$host] Unauthorized command: $username (as $sudo_user)" } ],
		[ 'not in the sudoers file', 	sub { die "[$host] User is not in the sudoers file: $username" } ],
		[ 'eof', 			sub { &no_match("[$host] (sudo) Premature EOF") } ],
		[ 'timeout', 			sub { die "[$host] (sudo) Timeout" } ],
		[ $shell_prompt ],
	);
}

if ( !defined $cmd ) {
	$exp->interact();
	$exp->soft_close();
	exit;
}

my @cmd_output;
#my $ret;
$exp->send("$cmd\n");
$exp->expect($int_opts->{'timeout'},
	[ '\r\n', 	sub {	push @cmd_output, $exp->before();
			print "$cmd_output[-1]\n" if ( !defined $int_opts->{'o'} && $#cmd_output > 0 );
			exp_continue } ],
#	[ '\r', 	sub { $ret .= $exp->before(); exp_continue } ],
	[ 'eof', 	sub { &no_match("[$host] (cmd) Premature EOF") } ],
	[ 'timeout', 	sub { die "[$host] (cmd) Timeout" } ],
	[ $shell_prompt ]
);
#@cmd_output = split /\n/, $ret; # or split /\r/, ... for qr/\n/ in $exp->expect
shift @cmd_output;

my $rc;
$exp->send("echo \$\?\n");
$exp->expect($int_opts->{'timeout'},
	[ '\r\n', 	sub { $rc = $exp->before(); exp_continue } ],
	[ 'eof', 	sub { &no_match("[$host] (rc) Premature EOF") } ],
	[ 'timeout', 	sub { die "[$host] (rc) Timeout" } ],
	[ $shell_prompt ]
);
$rc =~ s{^\Q$/\E}{}; # remove newline character from start of string

if ( $sudo ) {
	$exp->send("exit\n");
	$exp->expect($int_opts->{'timeout'}, [ $shell_prompt ]);
}

$exp->send("exit\n");
#$exp->expect($int_opts->{'timeout'}, 'logout');

#$exp->hard_close();
$exp->soft_close();

my $cmd_output_lines = scalar @cmd_output;
$int_opts->{'olines'} = $cmd_output_lines if $int_opts->{'olines'} == 0;

my $status_msg = "OK\n";
$status_msg = "Error (rc=$rc)\n" if $rc;
if ( defined $int_opts->{'o'} && $int_opts->{'o'} == 1 && $cmd_output_lines ) {
	$status_msg .= ( $int_opts->{'olines'} < $cmd_output_lines ) ? join("\n", @cmd_output[-$int_opts->{'olines'}..-1]) : join("\n", @cmd_output);
	$status_msg .= "\n";
}

if ( defined $odir ) {
	my $output_file = $odir . '/' . $host . '_' . "$pid.output";
        if ( open my $fh, '>', $output_file ) {
		print $fh join("\n", @cmd_output);
		close $fh;
	} else {
		$status_msg .=  "Can't create file $output_file: $!\n";
	}
}

print "[$host] [$pid] -> $status_msg";
exit $rc;

# end of script

sub no_match {
	my $message = shift;
	my $exp_output = $exp->before();
	$exp_output =~ s{^\Q$/\E}{};
	print $exp_output.$message."\n";
	exit -1;
}

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
	print "\nUsage: $0 [-help] [-version] [-u=username] [-p=password] [-sudo[=sudo_user]]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-o[=0|1] -olines=n -odir=path] [-v] <host> [<command>]\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sudo : Sudo to sudo_user and run <command> (default: root)\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default seconds)\n";
	print "\t -o : (Not defined) Display command output as it happens\n";
	print "\t      (0) Do not display command output\n";
	print "\t      (1) Buffer output; display it after command completion (useful for concurrent execution)\n";
	print "\t -olines : Ignore -o and display the last n lines of buffered output (default: 10 | full output: 0)\n";
	print "\t -odir : Directory in which the command output will be stored as a file (default: \$PWD -current folder-)\n";
	print "\t -v : Enable verbose messages\n";
	print "\t Use envoriment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t Encase <command> in quotes to pass it as a single argument\n";
	print "\t Omit <command> for interactive mode\n\n";
	exit;
}
