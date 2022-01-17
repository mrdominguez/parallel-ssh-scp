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

# SSH command-line utility with automatic authentication (no SSH keys required)
# Use -help for options

use strict;
use Expect;
use File::Basename;
use IO::Prompter;
use Time::HiRes qw( time );

our ($help, $version, $u, $p, $sudo, $bg, $via, $bu, $ru, $sshOpts, $timeout, $o, $olines, $odir, $et, $v, $d);

my $start = time() unless ( $et || $help || $version );

if ( $d ) {
	$Expect::Exp_Internal = 1;	# Set/unset 'exp_internal' debugging	
	$Expect::Debug = 1;		# Object debugging
}

if ( $version ) {
	print "SSH command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 6.0\n";
	print "Release date: 2022-01-15\n";
	exit;
}

my $timeout_default = 20;
my $olines_default = 10;
my $odir_default = $ENV{PWD};

&usage if $help;
die "Missing argument: <host>\nUse -help for options\n" if @ARGV < 1;

my $int_opts = {};
$int_opts->{'timeout'} = $timeout || $timeout_default;	# Use default value if 0 (or empty)

if ( defined $olines ) {
	$int_opts->{'o'} = 1;
} elsif ( defined $o ) {
	$int_opts->{'o'} = $o;
}

$int_opts->{'olines'} = $olines // $olines_default;
$odir = $odir_default if ( defined $odir && $odir eq '1' );

foreach my $opt ( keys(%{$int_opts}) ) {
	die "-$opt ($int_opts->{$opt}) is not an integer\n" if $int_opts->{$opt} =~ /\D/;
}

my ($host, $cmd) = @ARGV;

if ( $host =~ /(.+),([^\s].+[^\s])?/ ) {
	$host = $1;
	$via = $2 if $2;
}

if ( $host =~ /(.+)\@(.+)/ ) {
	$host = $2;
	$via ? $ru = $1 : $u = $1
}

if ( $v ) {
	print "timeout = $int_opts->{'timeout'} s\n";
	print "o = $int_opts->{'o'}\n" if defined $int_opts->{'o'};
	print "olines = $int_opts->{'olines'}\n";
	print "odir = $odir\n" if defined $odir;
	print "SSH_USER = $ENV{SSH_USER}\n" if $ENV{SSH_USER};
	print "SSH_PASS is set\n" if $ENV{SSH_PASS};
	print "via = $via\n" if $via;
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
}

my $ssh;
if ( $via ) {
	$via = "$bu\@$via" if ( $via !~ /\@/ && $bu );
	$ssh = "sft ssh --via $via ";
	$ssh .= "$ru\@" if $ru;
	$ssh .= $host
} else {
	$ssh = 'ssh -o StrictHostKeyChecking=no -o CheckHostIP=no';
	$ssh .= " $sshOpts" if $sshOpts;
	$ssh .= " $username\@$host"
}
#print "$ssh\n" if $v;

# \s will match newline, use literal space instead
my $shell_prompt = qr'\][\$\#] $';
#my $shell_prompt = qr' [%\#] ';

my $exp = new Expect;
$exp->raw_pty(0);
$exp->log_stdout(0);		# Set (1) -default-, unset (0) logging to STDOUT
#$exp->log_file("$0.log","a");	# Log session to file (a=append -default-, w=truncate)

# Catch the signal WINCH ("window size changed"), change the terminal size and propagate the signal to the spawned application
$exp->slave->clone_winsize_from(\*STDIN);
$SIG{WINCH} = \&winch;
sub winch {
	$exp->slave->clone_winsize_from(\*STDIN);
	kill WINCH => $exp->pid if $exp->pid;
	$SIG{WINCH} = \&winch;
}

print "[$host] Executing SSH... " if $v;

$exp->spawn($ssh) or die "Cannot spawn ssh: $!\n";

my $pid = $exp->pid();
my $pw_sent = 0;

print "PID: $pid\n" if $v;

my @exp_output;
$exp->expect($int_opts->{'timeout'},
  	  # Are you sure you want to continue connecting (yes/no/[fingerprint])?
	[ '\(yes/no(/.*)?\)\?\s*$',			sub {
							  print "The authenticity of host \'$host\' can't be established\n" if $v;
							  &send_yes() } ],
	[ qr/password.*:\s*$/i,				sub { &send_password() } ],
	[ qr/login:\s*$/i,				sub { $exp->send("$username\n"); exp_continue } ],
#	[ 'Host key verification failed',		sub { die "[$host] (auth) Host key verification failed\n" } ],
#	[ 'WARNING: REMOTE HOST IDENTIFICATION',	sub { die "[$host] (auth) Add correct host key in ~/.ssh/known_hosts\n" } ],
	[ '\r\n',					sub { &collect_output() } ],
	[ 'eof',					sub { &capture('(auth) EOF') } ],
	[ qr/Add to known_hosts\?.*/i,			sub { &send_yes() } ],
	  # Expect TIMEOUT
	[ 'timeout',					sub { &capture('(auth) Timeout') } ], 
#	[ $shell_prompt,				sub { print $exp->before() . $exp->match() unless defined $int_opts->{'o'} } ]
	[ $shell_prompt ]
);

@exp_output = ();
$pw_sent = 0;
my $sudo_user;
if ( $sudo ) {
	$sudo_user = $sudo eq '1' ? 'root' : $sudo;
	print "[$host] Sudoing to user $sudo_user\n" if $v;
	my $sudo_cmd1 = "sudo -i -u $sudo_user";
	my $sudo_cmd2 = "sudo su - $sudo_user";

	&send_sudo($sudo_cmd1);

	sub send_sudo {
		my $sudo_cmd = shift;
		$exp->send("$sudo_cmd\n");
		$exp->expect($int_opts->{'timeout'},
			  # If $password is undefined and ssh does not require it, sudo may still prompt for password...
			[ qr/password.*:\s*$/i,		sub { &send_password() } ],
			[ qr/sudo: unknown user: \w+/,	sub { &capture("(sudo) Unknown user $sudo_user") } ],
			[ qr/user \w+ does not exist/,	sub { &capture("(sudo) User $sudo_user does not exist") } ],
			[ 'not allowed to execute',	sub { &capture("(sudo) User $username not allowed to execute ...") } ],
			[ 'not in the sudoers file',	sub { &capture("(sudo) User $username not in the sudoers file") } ],
			[ 'Need at least 3 arguments',	sub {
							  print "[$host] Sudo issue... trying different sudo command\n";
							  &send_sudo($sudo_cmd2);
							  exp_continue } ],
#			[ '\r\n',			sub { exp_continue } ],
			[ '\r\n',			sub { &collect_output() } ],
			[ 'eof',			sub { &capture('(sudo) EOF') } ],
			[ 'timeout',			sub { &capture('(sudo) Timeout') } ],
			[ $shell_prompt ]
		)
	}
}

if ( !defined $cmd ) {
	$exp->send("\n");
	$exp->interact();
	$exp->soft_close();
	exit;
}

@exp_output = ();
$pw_sent = 0;
my $cmd_sent = 0;
$exp->send("$cmd\n");
$exp->expect($int_opts->{'timeout'},
	[ qr/password.*:\s*$/i,		sub { &send_password() } ],
	[ qr/sudo: unknown user: \w+/,	sub { &capture('(sudo command) Unknown user') } ],
	[ qr/user \w+ does not exist/,	sub { &capture('(sudo command) User does not exist') } ],
	[ 'not allowed to execute',	sub { &capture('(sudo command) User not allowed to execute ...') } ],
	[ 'not in the sudoers file',	sub { &capture('(sudo command) User not in the sudoers file') } ],
	[ '\r\n',			sub { $cmd_sent = 1 unless $cmd_sent; &collect_output() } ],
	[ 'eof',			sub { &capture('(cmd) EOF') } ],
	[ 'timeout',			sub { &capture('(cmd) Timeout') } ],
	[ $shell_prompt ]
);

my $rc;
unless ( $bg ) {
	$exp->send("echo \"(cmd) rc: \$\?\"\n");
	$exp->expect($int_opts->{'timeout'},
		[ '\r\n',	sub { ( $exp->before() && $exp->before =~ /\(cmd\) rc: \d+/ ) ? $rc = $exp->before() : exp_continue } ],
		[ 'eof',	sub { &capture('(rc) EOF') } ],
		[ 'timeout',	sub { &capture('(rc) Timeout') } ],
		[ $shell_prompt ]
	)
} else { $rc = 100 }

if ( $sudo ) {
	$exp->send("exit\n");
	$exp->expect($int_opts->{'timeout'}, [ $shell_prompt ]);
}

$exp->send("exit\n");
#$exp->expect($int_opts->{'timeout'}, 'logout');
#$exp->hard_close();
$exp->soft_close();

my $msg_status = "OK\n";
unless ( $bg ) {
	if ( defined $rc ) {
		($rc) = $rc =~ /: (.+)$/;
		$msg_status = "Error (RC=$rc)\n" if ( $rc != 0 );
	} else {
		$msg_status = "Unknown: Could not get exit code\n";
		$rc = 10;
	}
} else { $msg_status = "OK (BG)\n" }

my $msg_output = &format_output();
$msg_status .= $msg_output if $msg_output;

if ( defined $odir ) {
	my $output_file = $odir . '/' . $host . '_' . "$pid.output";
        if ( open my $fh, '>', $output_file ) {
		print $fh join("\n", @exp_output);
		close $fh;
	} else {
		$msg_status .= "Can't create file $output_file: $!\n";
	}
}

print "[$host] [$pid] -> $msg_status";
exit $rc;

END {
	printf("[$host] [$pid] Execution time: %0.03f s\n", &time() - $start) unless ( $et || $help || $version );
}

# End of script

sub capture {
	my $msg = shift;
	$msg = "[$host] $msg\n";
	my $exp_output = $exp->before() if $exp->before();
	$exp_output .= $exp->match() if $exp->match();
	$exp_output .= $exp->after() if $exp->after();

	if ( $exp_output ) {
		$exp_output =~ s/\r\n.*/\n/gs;
		$msg .= $exp_output;
	}

	print $msg;

	my $output = &format_output();
	print $output if $output;

	my $exit_code;
	if ( $msg =~ /\(auth\) EOF/ ) {
		$exit_code=11
	} elsif ( $msg =~ /\(auth\) Timeout/ ) {
		$exit_code=12
	} elsif ( $msg =~ /\(sudo\)/ ) {
		$exit_code=13
	} elsif ( $msg =~ /\(sudo\) EOF/ ) {
		$exit_code=14
	} elsif ( $msg =~ /\(sudo\) Timeout/ ) {
		$exit_code=15
	} elsif ( $msg =~ /\(sudo command\)/ ) {
		$exit_code=16
	} elsif ( $msg =~ /\(cmd\) EOF/ ) {
		$exit_code=17
	} elsif ( $msg =~ /\(cmd\) Timeout/ ) {
		$exit_code=18
	} elsif ( $msg =~ /\(rc\) EOF/ ) {
		$exit_code=19
	} elsif ( $msg =~ /\(rc\) Timeout/ ) {
		$exit_code=20
	}
	exit $exit_code;
}

sub collect_output {
	if ( $exp->before() ) {
		push @exp_output, $exp->before();
		if ( !defined $int_opts->{'o'} && scalar(@exp_output) > 0 ) {
			print scalar(@exp_output) == 1 ? "$exp_output[0]\n" : "$exp_output[-1]\n";
		}
	}
	exp_continue unless ( $bg && $cmd_sent && ( $exp->before() !~ $shell_prompt || $exp->after() !~ $shell_prompt ) );
}

sub format_output {
	shift @exp_output;
	my $exp_output_lines = scalar(@exp_output);
	$int_opts->{'olines'} = $exp_output_lines if $int_opts->{'olines'} == 0;

	my $output;
	if ( defined $int_opts->{'o'} && $int_opts->{'o'} == 1 && $exp_output_lines ) {
		$output .= ( $int_opts->{'olines'} < $exp_output_lines ) ? join("\n", @exp_output[-$int_opts->{'olines'}..-1]) : join("\n", @exp_output);
		$output .= "\n";
		return $output;
	}
}

sub send_password {
	if ( defined $password ) {
		if ( $pw_sent == 0 ) {
			$exp->send("$password\n");
			$pw_sent = 1;
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
	print "\t[-sudo[=sudo_user]] [-bg] [-via=[bastion_user@]bastion [-bu=bastion_user] [-ru=remote_user]]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-o[=0|1] -olines=n -odir=path] [-et] [-v] [-d]\n";
	print "\t<[username|remote_user@]host[,\$via]> [<command>]\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-, ignored when using -via or Okta credentials)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sudo : Sudo to sudo_user and run <command> (default: root)\n";
	print "\t -bg : Background mode (exit after sending command)\n";
	print "\t -via : Bastion host for Okta ASA sft client\n";
	print "\t   -bu : Bastion user\n";
	print "\t   -ru : Remote user\n";
	print "\t         (default: Okta username -sft login-)\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default s)\n";
	print "\t -o : (Not defined) Display command output as it happens\n";
	print "\t      (0) Do not display command output\n";
	print "\t      (1) Buffer the output and display it after command completion (useful for concurrent execution)\n";
	print "\t -olines : Display the last n lines of buffered output (default: $olines_default | full output: 0, implies -o=1)\n";
	print "\t -odir : Directory in which the command output will be stored as a file (default: \$PWD -current folder-)\n";
	print "\t -et : Hide execution time\n";
	print "\t -v : Enable verbose messages\n";
	print "\t -d : Expect debugging\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t Encase <command> in quotes to pass it as a single argument\n";
	print "\t Omit <command> for interactive mode\n\n";
	exit;
}
