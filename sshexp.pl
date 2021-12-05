#!/usr/bin/perl -ws

# Copyright 2021 Mariano Dominguez
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
use Scalar::Util qw(looks_like_number);

our ($help, $version, $u, $p, $sudo, $via, $ou, $sshOpts, $timeout, $o, $olines, $odir, $v, $d);

if ( $d ) {
	$Expect::Exp_Internal = 1;	# Set/unset 'exp_internal' debugging	
	$Expect::Debug = 1;		# Object debugging
}

if ( $version ) {
	print "SSH command-line utility\n";
	print "Author: Mariano Dominguez\n";
	print "Version: 4.1\n";
	print "Release date: 2021-12-03\n";
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
	$via ? $ou = $1 : $u = $1
}

if ( $v ) {
	print "timeout = $int_opts->{'timeout'} seconds\n";
	print "o = $int_opts->{'o'}\n" if defined $int_opts->{'o'};
	print "olines = $int_opts->{'olines'}\n";
	print "odir = $odir\n" if defined $odir;
	print "SSH_USER = $ENV{SSH_USER}\n" if $ENV{SSH_USER};
	print "SSH_PASS is set\n" if $ENV{SSH_PASS};
	print "via = $via\n" if $via;
	print "ou = $ou\n" if $ou;
	print "sshOpts = $sshOpts\n" if $sshOpts;
}

if ( $u && $u eq '1' && !$via ) {
        $u = prompt "Username [$ENV{USER}]:", -in=>*STDIN, -timeout=>30, -default=>"$ENV{USER}";
        die "Timed out\n" if $u->timedout;
	print "Using default username\n" if $u->defaulted;
}
my $username = $u || $ENV{SSH_USER} || $ENV{USER};
print "username = $username\n" if $v;

if ( $p && $p eq '1' && !$via ) {
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
	$ssh = "sft ssh --via $via ";
	$ssh .= "$ou\@" if $ou;
	$ssh .= $host
} else {
	$ssh = 'ssh -o StrictHostKeyChecking=no -o CheckHostIP=no';
	$ssh .= " $sshOpts" if $sshOpts;
	$ssh .= " $username\@$host"
}
#print "$ssh\n" if $v;

# \s will match newline, use literal space instead
my $shell_prompt = qr'\][\$\#] $';

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

$exp->expect($int_opts->{'timeout'},
  	  # Are you sure you want to continue connecting (yes/no/[fingerprint])?
	[ '\(yes/no(/.*)?\)\?\s*$',		sub { print "The authenticity of host \'$host\' can't be established\n" if $v;
						  &send_yes() } ],
	[ qr/password.*:\s*$/i,			sub { &send_password() } ],
	[ qr/login:\s*$/i,			sub { $exp->send("$username\n"); exp_continue } ],
	[ 'Host key verification failed',	sub { die "[$host] (auth) Host key verification failed\n" } ],
	[ 'WARNING: REMOTE HOST IDENTIFICATION',	sub { die "[$host] (auth) Add correct host key in ~/.ssh/known_hosts\n" } ],
	[ 'eof',				sub { &capture("[$host] (auth) EOF\n") } ],
	[ qr/Add to known_hosts\?.*/i,		sub { &send_yes() } ],
	  # Expect TIMEOUT
	[ 'timeout',				sub { die "[$host] (auth) Timeout\n" } ], 
	[ $shell_prompt ]
);

$pw_sent = 0;
my $sudo_user;
if ( $sudo ) {
	my $sudo_cmd;
	$sudo_user = $sudo eq '1' ? 'root' : $sudo;
	print "[$host] Sudoing to user $sudo_user\n" if $v;
#	$sudo_cmd = "sudo su - $sudo_user";
	$sudo_cmd = "sudo -i -u $sudo_user";

	$exp->send("$sudo_cmd\n");
	$exp->expect($int_opts->{'timeout'},
 		  # If $password is undefined and ssh does not require it, sudo may still prompt for password...
		[ qr/password.*:\s*$/i,		sub { &send_password() } ],
		[ 'unknown',			sub { &capture("[$host] (sudo) ") } ],
		[ 'does not exist',		sub { &capture("[$host] (sudo) ") } ],
		[ 'not allowed to execute',	sub { &capture("[$host] (sudo) ") } ],
		[ 'not in the sudoers file',	sub { &capture("[$host] (sudo) ") } ],
		[ '\r\n',			sub { exp_continue } ],
		[ 'eof',			sub { &capture("[$host] (sudo) EOF\n") } ],
		[ 'timeout',			sub { die "[$host] (sudo) Timeout\n" } ],
		[ $shell_prompt ]
	);
}

if ( !defined $cmd ) {
	my $user = $sudo ? $sudo_user : $username;
	my $msg = '';
	
	# Comment out to remove message
	$msg = "echo -e \"#\\n# Connected to `hostname -f`\\n# Logged in as `whoami`";
	$msg .= " through sudo" if $sudo;
	$msg .= "\\n#\"";
	$msg .= '; date';

	$exp->send("$msg\n");
	$exp->interact();
	$exp->soft_close();
	exit;
}

my @cmd_output;
$pw_sent = 0;
$exp->send("$cmd\n");
$exp->expect($int_opts->{'timeout'},
	[ qr/password.*:\s*$/i,		sub { &send_password() } ],
	[ 'unknown',			sub { &capture("[$host] (sudo command) ") } ],
	[ 'does not exist',		sub { &capture("[$host] (sudo command) ") } ],
	[ 'not allowed to execute',	sub { &capture("[$host] (sudo command) ") } ],
	[ 'not in the sudoers file',	sub { &capture("[$host] (sudo command) ") } ],
	[ '\r\n',			sub { push @cmd_output, $exp->before() if $exp->before();
				 	  print "$cmd_output[-1]\n" if ( !defined $int_opts->{'o'} && $#cmd_output > 0 && $exp->before() );
					  exp_continue } ],
	[ 'eof',			sub { &capture("[$host] (cmd) EOF\n") } ],
	[ 'timeout',			sub { die "[$host] (cmd) Timeout\n" } ],
	[ $shell_prompt ]
);

shift @cmd_output;

my $rc;
$exp->send("echo \$\?\n");
$exp->expect($int_opts->{'timeout'},
	[ '\r\n',	sub { $rc = $exp->before(); exp_continue } ],
	[ 'eof',	sub { &capture("[$host] (rc) EOF\n") } ],
	[ 'timeout',	sub { die "[$host] (rc) Timeout\n" } ],
	[ $shell_prompt ]
);

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
if ( $rc ) {
	$status_msg = "Error";
	if ( looks_like_number($rc) ) {
		$status_msg .= " (RC=$rc)\n"
	} else {
		$status_msg .= ": Unexpected exit code\n";
		$rc = -1;
	}
}

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
		$status_msg .= "Can't create file $output_file: $!\n";
	}
}

print "[$host] [$pid] -> $status_msg";
exit $rc;

# End of script

sub capture {
	my $msg = shift;
	my $exp_output = $exp->before() if $exp->before();
	$exp_output .= $exp->match() if $exp->match();
	$exp_output .= $exp->after() if $exp->after();
	if ( $exp_output ) {
		$exp_output =~ s/\r\n.*/\n/gs;
		$msg .= $exp_output;
	}
	print $msg;
	exit -1;
}

sub send_password {
	if ( defined $password ) {
		if ( $pw_sent == 0 ) {
			$pw_sent = 1;
			$exp->send("$password\n");
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
	print "\t[-sudo[=sudo_user]] [-via=[bastion_user@]bastion [-ou=okta_user]]\n";
	print "\t[-sshOpts=ssh_options] [-timeout=n] [-o[=0|1] -olines=n -odir=path] [-v] [-d]\n";
	print "\t<[username|okta_user@]host[,\$via]> [<command>]\n\n";

	print "\t -help : Display usage\n";
	print "\t -version : Display version information\n";
	print "\t -u : Username (default: \$USER -current user-, ignored when using -via or Okta credentials)\n";
	print "\t -p : Password or path to password file (default: undef)\n";
	print "\t -sudo : Sudo to sudo_user and run <command> (default: root)\n";
	print "\t -via : Bastion host for Okta ASA sft client\n";
	print "\t        (Default bastion_user: Okta username -sft login-)\n";
	print "\t   -ou : Okta user (default: Okta username)\n";
	print "\t -sshOpts : Additional SSH options\n";
	print "\t            (default: -o StrictHostKeyChecking=no -o CheckHostIP=no)\n";
	print "\t            Example: -sshOpts='-o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'\n";
	print "\t -timeout : Timeout value for Expect (default: $timeout_default seconds)\n";
	print "\t -o : (Not defined) Display command output as it happens\n";
	print "\t      (0) Do not display command output\n";
	print "\t      (1) Buffer the output and display it after command completion (useful for concurrent execution)\n";
	print "\t -olines : Ignore -o and display the last n lines of buffered output (default: 10 | full output: 0)\n";
	print "\t -odir : Directory in which the command output will be stored as a file (default: \$PWD -current folder-)\n";
	print "\t -v : Enable verbose messages\n";
	print "\t -d : Expect debugging\n";
	print "\t Use environment variables \$SSH_USER and \$SSH_PASS to pass credentials\n";
	print "\t Encase <command> in quotes to pass it as a single argument\n";
	print "\t Omit <command> for interactive mode\n\n";
	exit;
}
