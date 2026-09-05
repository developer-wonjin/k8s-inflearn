#!/usr/bin/perl
# 이미 작성된 md의 ```bash 블록에서 후행 주석(`  #`)의 열을 블록별로 다시 맞춘다.
# heredoc 내부, 들여쓰기된 연속 줄, 단독 주석 줄은 대상에서 제외한다.
use strict; use warnings; use utf8;
binmode(STDIN, ':encoding(UTF-8)'); binmode(STDOUT, ':encoding(UTF-8)');
my @l = <STDIN>; chomp @l;
my @out; my $i = 0;
while ($i <= $#l) {
  if ($l[$i] =~ /^```bash\s*$/) {
    my $j = $i + 1;
    $j++ while $j <= $#l && $l[$j] !~ /^```\s*$/;
    my @idx; my $max = 0; my $here;
    for my $k ($i+1 .. $j-1) {
      my $x = $l[$k];
      if (defined $here) { $here = undef if $x =~ /^\Q$here\E\s*$/; next }
      if ($x =~ /<<'?([A-Za-z_]\w*)'?/) { $here = $1 }
      next if $x =~ /^\s/;                 # 들여쓰기된 연속 줄 제외
      next if $x =~ /^#/;                  # 단독 주석 줄 제외
      next unless $x =~ /\s{2,}#/;
      my $p = index($x, '  #');
      next if $p < 0;
      my $cmd = substr($x, 0, $p); $cmd =~ s/\s+$//;
      push @idx, [$k, $cmd, substr($x, $p + 2)];
      $max = length($cmd) if length($cmd) > $max;
    }
    my %new = map { $_->[0] => sprintf("%-*s  %s", $max, $_->[1], $_->[2]) } @idx;
    push @out, $l[$i];
    push @out, (exists $new{$_} ? $new{$_} : $l[$_]) for ($i+1 .. $j);
    $i = $j + 1; next;
  }
  push @out, $l[$i]; $i++;
}
print "$_\n" for @out;
