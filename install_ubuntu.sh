#!/usr/bin/sh
apt update
apt -y install perl perl-tk libbrowser-open-perl
cpan CPAN
cpan PDF::API2
cpan Tk::Balloon