#!/usr/bin/perl
# 네이버 카페 게시글 본문을 텍스트로 변환 (정규식 폭주 방지: 수동 스캔)
use strict; use warnings;
local $/; my $j = <STDIN>;

sub grab {                      # "key":"...." 값을 이스케이프 고려해 잘라냄
  my ($key) = @_;
  my $p = index($j, "\"$key\":\"");
  return undef if $p < 0;
  my $i = $p + length($key) + 4;
  my $out = '';
  while ($i < length($j)) {
    my $c = substr($j, $i, 1);
    if ($c eq '\\') { $out .= substr($j, $i, 2); $i += 2; next }
    last if $c eq '"';
    $out .= $c; $i++;
  }
  return $out;
}

sub unesc {
  my ($s) = @_;
  return '' unless defined $s;
  $s =~ s/\\u([0-9a-fA-F]{4})/chr(hex($1))/ge;
  $s =~ s/\\n/\n/g; $s =~ s/\\t/\t/g; $s =~ s/\\r//g;
  $s =~ s/\\"/"/g; $s =~ s/\\\//\//g; $s =~ s/\\\\/\\/g;
  return $s;
}

my $subj = unesc(grab('subject'));
my $html = grab('contentHtml');
die "contentHtml 없음\n" unless defined $html && length $html;
$_ = unesc($html);

print "### $subj\n\n" if length $subj;

s/<script\b.*?<\/script>//gis;
s/<style\b.*?<\/style>//gis;
s/<br\s*\/?>/\n/gi;
s/<\/(p|div|tr|li|h[1-6]|pre|table)>/\n/gi;
s/<li\b[^>]*>/- /gi;
s/<\/td>/\t/gi;
s/<img[^>]*?src="([^"]*)"[^>]*>/\n[IMG $1]\n/gi;
s/<a[^>]*?href="([^"]*)"[^>]*>(.*?)<\/a>/$2 <$1>/gis;
s/<[^>]+>//gs;

my %e = ('lt'=>'<','gt'=>'>','amp'=>'&','quot'=>'"','apos'=>"'",'nbsp'=>' ');
s/&#(\d+);/chr($1)/ge;
s/&#x([0-9a-fA-F]+);/chr(hex($1))/ge;
s/&(\w+);/exists $e{$1} ? $e{$1} : "&$1;"/ge;

s/\x{200b}//g;
s/[ \t]+\n/\n/g;
s/\n{3,}/\n\n/g;
print;
