#!/usr/bin/perl
# 사용법: anchors.pl <md파일...>
# 마크다운 내부 링크의 앵커(#...)가 실제 헤딩과 맞는지 검사한다.
use strict; use warnings; use utf8;
use File::Basename; use File::Spec;
binmode(STDOUT, ':encoding(UTF-8)');

sub slugs {
  my ($p) = @_; my @s;
  open my $fh, '<:encoding(UTF-8)', $p or return ();
  while (my $l = <$fh>) {
    chomp $l;
    next unless $l =~ /^\#{1,6}\s+(.+)$/;
    my $t = lc $1;
    $t =~ s/`//g; $t =~ s/\*\*//g;
    $t =~ s/[^\w\s가-힣-]//g;
    $t =~ s|\s|-|g;
    push @s, $t;
  }
  close $fh;
  return @s;
}

my $bad = 0;
for my $f (@ARGV) {
  my $dir = dirname($f);
  open my $fh, '<:encoding(UTF-8)', $f or next;
  while (my $l = <$fh>) {
    while ($l =~ /\]\(([^)#]*)#([^)]+)\)/g) {
      my ($tgt, $anc) = ($1, $2);
      my $p = ($tgt eq '') ? $f : File::Spec->catfile($dir, $tgt);
      unless (-f $p) { print "  없는 파일: $f -> $tgt\n"; $bad++; next }
      my %s = map { $_ => 1 } slugs($p);
      unless ($s{$anc}) { print "  깨진 앵커: $f -> $tgt#$anc\n"; $bad++ }
    }
  }
  close $fh;
}
print $bad ? "  => 문제 $bad 건\n" : "  => 링크 앵커 전부 정상\n";
exit($bad ? 1 : 0);
