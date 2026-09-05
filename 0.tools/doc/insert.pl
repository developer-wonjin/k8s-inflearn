use strict; use warnings; use utf8;
binmode(STDOUT,':utf8');
my $sec = shift @ARGV;
open my $sh,'<:utf8',$sec or die $!; my @s = <$sh>; close $sh;
open my $fh,'<:utf8',$ARGV[0] or die $!; my @l = <$fh>; close $fh;
my $done = 0; my @out;
for my $line (@l) {
  if (!$done && $line =~ /^## /) { push @out, @s; $done = 1 }
  push @out, $line;
}
print @out;
