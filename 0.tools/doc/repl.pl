#!/usr/bin/perl
# repl.pl FILE START END NEWCONTENTFILE  → FILE의 START~END 줄을 NEWCONTENTFILE 내용으로 교체
use strict; use warnings;
my ($file,$s,$e,$new) = @ARGV;
open my $fh,'<',$file or die $!; my @l = <$fh>; close $fh;
open my $nh,'<',$new  or die $!; my @n = <$nh>; close $nh;
splice(@l, $s-1, $e-$s+1, @n);
open my $oh,'>',$file or die $!; print $oh @l; close $oh;
