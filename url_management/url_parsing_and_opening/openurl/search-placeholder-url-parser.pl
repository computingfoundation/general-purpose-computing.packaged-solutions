#!/usr/bin/env perl
# 
# File:
#   search-placeholder-url-parser.pl
# 
# Description:
#   Replace one or more "{search\D}" placeholders in one or more URLs with a
#   search query, where D is the space delimiter of the URL.
# 
# Example:
#   search-placeholder-url-parser.pl \
#       "https://duckduckgo.com/?q={search\+}&iax=1&ia=images" \
#       "earth's biosphere"
# 
#   # output: "https://duckduckgo.com/?q=earth%27s+biosphere&iax=1&ia=images"
# 
# Usage:
#   search-placeholder-url-parser.pl <URLs> <search_queries...>
# 
#       <URLs>: must be in the first argument and delimited by "<|>"
#       <search_queries...>: delimited by $SEARCH_QUERY_DELIMITER; can be passed
#           in any number of arguments (all arguments after the first are
#           joined).
# 
# Multiple search queries for a URL:
#   A URL can allow multiple search queires by using multiple {search\D}
#   placeholders. The position of a placeholder corresponds with the position of
#   the search query used to replace it. If a placeholder does not have a search
#   query, it is replaced with an empty string.
# 
# Search query options:
#   Search query options can be used to change and modify the search query used
#   for a placeholder. They are specified with a bang ("!") and placed after the
#   delimiter specifier. They are the following:
# 
#     !<N>:    Use search query N (e.g. {search!3\D})
#     !W<P>:   Use word at position P of the search query only; will work for
#              multiple words (e.g. {search!W2!W5!W6\+})
#     !U[P]:   Make all letters of word at position P of the search query
#              uppercase (e.g. {search!U1!U3\+}); omit P for all words
#     !C:      Capitalize all words of the search query
#     !R:      Reverse all words of the search query
#     !M:      Remove all commas of the search query
# 
# Multiple URLs:
#   Multiple URLs can be passed in at once. They must be passed in the first
#   argument and delimited by "<|>". Each of their {search\D} placeholders will
#   be replaced with the same search queries (exepct those that changed their
#   search query to another with the !<P> option). The parsed URLs will be
#   returned as a single string in the same format (delimited by "<|>").
# 
# Notes:
#   Unsafe URL characters in all URLs will be encoded. An unsafe URL character
#   can be escaped with two backslashes to keep it from being encoded. This also
#   applies to the delimiter in the search placeholder.
# 
# URL data delimiters:
#   This script was created mainly as a utility for other scripts. For this
#   reason, it takes into account "<>" delimiters in between the URL "<|>"
#   delimiters which can be used to pass important data with the URLs.
#   Everything after the first occurrence of a "<>" delimiter is left as is and
#   the string before it is considered the URL. The return string will be in the
#   same format (i.e. "url1[<>data1<>data2...]<|>url2[<>data1<>data2...]<|>
#   url3...").
# 

use strict;
use warnings;
use URI::Escape;

# ======= CONFIGURATIONS ==============

# Delimiter used to separate search queries
my $SEARCH_QUERY_DELIMITER = '%%';

# Maximum {search\D} placeholders allowed per URL
my $MAXIMUM_SEARCH_PLACEHOLDERS_ALLOWED_PER_URL = 8;

# ======= ! CONFIGURATIONS ==============

# ASCII ranges for unsafe URL characters in the search queries
# Notes:
#   -The following ranges include almost all unsafe URL characters and disclude
#    [#$%&-=?_ ] (to include these with the exception of the space, use
#    "\x00-\x1F\x21-\x2C\x3B-\x40\x5B-\x60\x7B-\xFF" instead).
#   -Important: The space character must not be included as spaces are replaced
#    by the search placeholder delimiter.
my $SEARCH_QUERY_ASCII_ESCAPE_RANGES = '\x00-\x1F\x21\x22\x24\x27-\x2C\x3B\x3C';
$SEARCH_QUERY_ASCII_ESCAPE_RANGES .= '\x3E\x40\x5B-\x5E\x60\x7B-\xFF';

# ASCII ranges for unsafe URL characters in all parts of the URL except the
# search queries
my $URI_ASCII_ESCAPE_RANGES = $SEARCH_QUERY_ASCII_ESCAPE_RANGES.'\x20';

if (scalar @ARGV < 1) {
  # Script error messages begin with "error" followed by an underscore so they
  # can be distinguished from URL and search query formatting error messages.
  print 'error_: invalid number of arguments: '.scalar @ARGV."\n";
  exit 1;
}

# Remove leading "<|>" delimiters and their surrounding spaces as they cause
# empty array elements to be created at the beginning of the array.
$ARGV[0] =~ s/^(\s*<|>\s*)*//;

my @ARG_URLS_W_DATA = split(/<\|>/, $ARGV[0]);
if (scalar @ARG_URLS_W_DATA == 0) {
  exit;
}

shift @ARGV;
my $ARG_SEARCH_QUERIES = join(' ', @ARGV);
$ARG_SEARCH_QUERIES =~ s/^\s+|\s+$//g;

# Remove leading search query delimiters and their surrounding spaces so there
# are no empty search queries at the beginning. This means the first non-empty
# search query is shifted to the first position. Empty search queries after it
# are allowed.
$ARG_SEARCH_QUERIES =~ s/^(\s*$SEARCH_QUERY_DELIMITER\s*)*//;

my @SEARCH_QUERIES = split(/\s*$SEARCH_QUERY_DELIMITER\s*/,
    $ARG_SEARCH_QUERIES);

# escapeUrlSection
#   Escape unsafe URL characters in a section of a URL.
#   Parameters:
#     1. The section of the URL to escape (passed by reference)
#     2. The ASCII escape range(s) to use (passed by reference)
sub escapeUrlSection {
  my $urlSect = ${(shift)};
  my $uriEscpRngs = ${(shift)};
  my @urlEscpSects = split(/\\\\/, $urlSect);
  my $retStr = uri_escape($urlEscpSects[0], $uriEscpRngs);

  if (scalar @urlEscpSects > 1) {
    for my $indx (1..$#urlEscpSects) {
      my $urlEscpSect = $urlEscpSects[$indx];
      my $frstChar = substr($urlEscpSect, 0, 1);
      my $remChars = substr($urlEscpSect, 1, length($urlEscpSect));

      $retStr .= $frstChar.uri_escape($remChars, $uriEscpRngs);
    }
  }
  return $retStr;
}

my $RETURN_STRING;

for my $urlWData (@ARG_URLS_W_DATA) {
  my ($url) = $urlWData =~ /(.*?(?=<>)|.*)/;
  my ($urlData) = $urlWData =~ /(<>.*)/;
  my $srchPlhNo;
  my $urlEndPos = 0;
  my $fnlUrl;

  while ($url =~ /(.*?)(\{search([^\\]*)(?:\\([^}]*))})/g) {
    my ($txtBefr, $plh, $opts, $spcDelim) = ($1, $2, $3, $4);
    my $optSrchQryPos;
    my @optOnlyWrdsPos;
    my @optUpprCaseWrdsPos;
    my $optCptlz;
    my $optRevrs;
    my $optRemCommas;

    $srchPlhNo++;

    # ============================================
    #   Validate the search placeholder
    # ============================================

    if ($srchPlhNo == 1 && $txtBefr eq '') {
      print "error: {search\\D}\n  placeholder cannot be at the very\n ",
          " beginning of a URL; URL:\n  $url\n";
      exit 1;
    } elsif ($spcDelim eq '') {
      print "error: delimiter D\n  missing for {search\\D} placeholder;\n ",
          " URL:\n  $url\n";
      exit 1;
    } elsif (length($spcDelim) > 7) {
      print "error: delimiter D\n  for {search\\D} placeholder too long;\n ",
          " Length: ".length($spcDelim)."\n  Delimiter: \"$spcDelim\"\n ",
          " URL:\n  $url\n";
      exit 1;
    } elsif ($srchPlhNo > $MAXIMUM_SEARCH_PLACEHOLDERS_ALLOWED_PER_URL) {
      print "error: cannot use\n  more than",
          " $MAXIMUM_SEARCH_PLACEHOLDERS_ALLOWED_PER_URL {search\\D}\n ",
          " placeholders; URL:\n  $url\n";
      exit 1;
    }

    # ===============================================
    #   Process the search placeholder's options
    # ===============================================

    if ($opts ne '') {
      if ($opts !~ m/^(!([0-9]{1,2}|[WU][0-9]{0,2}|[CRM]))+$/) {
        print "error: one or more\n  invalid options in placeholder\n  $plh;\n",
            "  URL:\n  $url\n";
        exit 1;
      }

      while ($opts =~ /!([0-9]{1,2}|[WU][0-9]{0,2}|[CRM])/g) {
        my $opt = $1;

        if ($opt =~ qr/^[0-9]{1,2}$/) {
          if ($opt < 1 || $opt > $MAXIMUM_SEARCH_PLACEHOLDERS_ALLOWED_PER_URL) {
            print "error: search query\n  position $opt in placeholder\n ",
                " $plh\n  out of range; valid range is",
                " 1-$MAXIMUM_SEARCH_PLACEHOLDERS_ALLOWED_PER_URL;\n  URL:\n ",
                " $url\n";
            exit 1;
          }

          $optSrchQryPos = $opt;
        } elsif ($opt =~ qr/^W([0-9]{0,2})$/) {
            if ($1 ne '') {
              push @optOnlyWrdsPos, $1 - 1;
            } else {
              print "error: position P\n  missing for option \"!W[P]\" in\n ",
                  " placeholder $plh\n  URL:\n  $url\n";
              exit 1;
            }
        } elsif ($opt =~ qr/^U([0-9]{0,2})$/) {
            if ($1 ne '') {
              push @optUpprCaseWrdsPos, $1 - 1;
            } else {
              $optUpprCaseWrdsPos[0] = -2;
            }
        } elsif ($opt eq 'C') {
          $optCptlz = 1;
        } elsif ($opt eq 'R') {
          $optRevrs = 1;
        } elsif ($opt eq 'M') {
          $optRemCommas = 1;
        }
      }
    }

    # ============================================
    #   Process the current URL section
    # ============================================

    $urlEndPos = $+[0];

    $fnlUrl .= escapeUrlSection(\$txtBefr, \$URI_ASCII_ESCAPE_RANGES);

    # ============================================
    #   Process the search query for the search placeholder
    # ============================================

    my $srchQryIndx;

    if (defined($optSrchQryPos)) {
      $srchQryIndx = $optSrchQryPos - 1;
    } else {
      $srchQryIndx = $srchPlhNo - 1;
    }

    my $srchQry = $SEARCH_QUERIES[$srchQryIndx];

    if (defined($srchQry)) {
      if (@optOnlyWrdsPos) {
        my @srchQryWrds = $srchQry =~ /\S+\s*/g;
        $srchQry = '';
        for my $pos (@optOnlyWrdsPos) {
          if ($pos > scalar @srchQryWrds - 1) {
            next;
          }
          $srchQry .= $srchQryWrds[$pos];
        }
        $srchQry =~ s/\s+$//g;
      }

      if (@optUpprCaseWrdsPos) {
        if ($optUpprCaseWrdsPos[0] == -2) {
          $srchQry = uc($srchQry);
        } else {
          my @srchQryWrds = $srchQry =~ /\S+\s*/g;
          for my $pos (@optUpprCaseWrdsPos) {
            if ($pos > scalar @srchQryWrds - 1) {
              next;
            }
            $srchQryWrds[$pos] = uc($srchQryWrds[$pos]);
          }
          $srchQry = join('', @srchQryWrds);
        }
      }

      if ($optCptlz) {
        $srchQry =~ s/\b(\w)/\U$1/g;
      }

      if ($optRevrs) {
        $srchQry = join('', reverse split(/(\s+)/, $srchQry));
      }

      if ($optRemCommas) {
        $srchQry =~ s/%2C//g;
      }

      $srchQry = escapeUrlSection(\$srchQry,
          \$SEARCH_QUERY_ASCII_ESCAPE_RANGES);

      $srchQry =~ s/\s/$spcDelim/g;

      $fnlUrl .= $srchQry;
    }
  } #!while URL sections and placeholders

  my $urlEnd = substr($url, $urlEndPos);
  
  if ($urlEnd ne '') {
    $fnlUrl .= escapeUrlSection(\$urlEnd, \$URI_ASCII_ESCAPE_RANGES);
  }

  my $fnlStr = ($urlData) ? "$fnlUrl$urlData" : $fnlUrl;

  $RETURN_STRING .= "$fnlStr<|>";
} #!for argument URLs with data

print substr($RETURN_STRING, 0, -3)."\n";

