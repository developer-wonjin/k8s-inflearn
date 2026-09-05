#!/usr/bin/perl
# md 파일의 ```bash 블록 안에서 'cmd¦comment' 를 블록별로 정렬한다.
use strict; use warnings; use utf8;
binmode(STDIN, ':utf8'); binmode(STDOUT, ':utf8');
my @l = <STDIN>; chomp @l;
my @out; my $i = 0;
while ($i <= $#l) {
  if ($l[$i] =~ /^```bash\s*$/) {
    my $j = $i + 1;
    $j++ while $j <= $#l && $l[$j] !~ /^```\s*$/;
    my $max = 0;
    for my $k ($i+1 .. $j-1) {
      next unless $l[$k] =~ /¦/;
      my ($c) = split /¦/, $l[$k], 2; $c =~ s/\s+$//;
      $max = length($c) if length($c) > $max;
    }
    push @out, $l[$i];
    for my $k ($i+1 .. $j-1) {
      if ($l[$k] =~ /¦/) {
        my ($c,$m) = split /¦/, $l[$k], 2; $c =~ s/\s+$//; $m =~ s/^\s+//;
        push @out, sprintf("%-*s  # %s", $max, $c, $m);
      } else { push @out, $l[$k] }
    }
    push @out, $l[$j];
    $i = $j + 1; next;
  }
  push @out, $l[$i]; $i++;
}
print "$_\n" for @out;
