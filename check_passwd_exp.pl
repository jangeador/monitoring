#!/usr/bin/perl
# Copyright (C) 2017 Martin Scharm <https://binfalse.de/contact/>
#
# This file is part of bf-monitoring.
# <https://binfalse.de/software/nagios/>
# <https://github.com/binfalse/monitoring>
# 
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


use strict;
use warnings;

use Net::LDAP;
use Getopt::Long;



sub get_days {
	my $seconds = shift;
	return int($seconds/(24*60*60)) . "d";
}

sub ldap_to_unix_time {
	my $ldap = shift;
	return $ldap / 10000000 - ((1970 - 1601) * 365 - 3 + (1970 - 1601) / 4) * 86400;
}

sub unix_to_ldap_time {
	my $unix = shift;
	return ($unix + ((1970 - 1601) * 365 - 3 + (1970 - 1601) / 4) * 86400) * 10000000;
}

sub ymd {
	my $t = shift;
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime ($t);
	return sprintf ("%.4d-%.2d-%.2d", ($year + 1900), $mon, $mday);
}

sub usage {
	my $msg = shift;
	print $msg . "\n" if $msg;
	print "Usage: $0 --ldapserver <LDAP SERVER> --ldapbase <LDAP BASE DN> [--max-age <SECONDS>] [--warning <SECONDS>] [--critical <SECONDS>] [--ignore-expired]\n";
	print "		max-age in seconds as configured in your institution, defaults to 999*24*60*60 (999 days)\n";
	print "		warning defaults to 30*24*60*60 (30 days)\n";
	print "		critical defaults to 5*24*60*60 (5 days)\n";
	exit 23;
}


my $warning = 30*24*60*60;
my $critical = 5*24*60*60;
my $maxage = 999*24*60*60;
my $ldapserver = "";
my $ldapbase = "";
my $ignoreexpired = '';


GetOptions (
        "ldapserver|s=s" => \$ldapserver,
        "ldapbase|b=s"   => \$ldapbase,
        "ignore-expired|i" => \$ignoreexpired,
        "max-age|m=s"   => \$maxage,
        "warning|w:i"  => \$warning,
        "critical|c:i"  => \$critical)
or usage ("Error in command line arguments\n");


my $ldap = Net::LDAP->new ($ldapserver) or usage ($@);
$ldap->bind;

my $result = $ldap->search (
    base   => $ldapbase,
    filter => "(&(objectClass=User)(objectClass=posixAccount))",
);
$ldap->unbind;


usage ($result->error) if $result->code;


my %ok = ();
my %problem = ();
my $serious = 1;


foreach my $entry ($result->entries) {
	my $pwd_age = time() - ldap_to_unix_time ($entry->get_value("PWDLASTSET"));
	my $last_day = ldap_to_unix_time ($entry->get_value("PWDLASTSET")) + $maxage;
	if ($entry->get_value("ACCOUNTEXPIRES") == 0)
	{
		$ok{$entry->get_value("PWDLASTSET") + unix_to_ldap_time (time ())} = sprintf ("%s: does not expire (%s) ", $entry->get_value("gecos"), ymd ($last_day));
	}
	else
	{
		my $time_left = $last_day - time();
        next if ($time_left < 0 and $ignoreexpired);
		if ($time_left > $warning) {
			$ok{$entry->get_value("PWDLASTSET")} = sprintf ("%s: %s left (%s) ", $entry->get_value("gecos"), get_days ($time_left), ymd ($last_day));
		}
		else {
			$serious = 2 if ($time_left < $critical);
			$problem{$entry->get_value("PWDLASTSET")} = sprintf ("%s: %s left (%s) ", $entry->get_value("gecos"), get_days ($time_left), ymd ($last_day));
		}
	}
}



if (keys %problem == 0) {
	print "all " . $result->count . " accounts ok|";
	foreach my $key (sort keys %ok) {
		print $ok{$key};
	}
	print "\n";
	exit 0;
}
else {
	print "serious! " if ($serious == 2);
	print ((keys %problem) . " problematic accounts: ");
	foreach my $key (sort keys %problem) {
		print $problem{$key};
	}
	print "|";
	foreach my $key (sort keys %ok) {
		print $ok{$key};
	}
	exit $serious;
}

