#!/usr/bin/sh
apt -y install perl perl-tk
cpan CPAN
cpan install PDF::API2
cpan Tk::Balloon