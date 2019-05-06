#! /usr/bin/env perl
#-*-Perl-*- This line forces emacs to use Perl mode.

##############################################################################
## YASK: Yet Another Stencil Kernel
## Copyright (c) 2014-2019, Intel Corporation
## 
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to
## deal in the Software without restriction, including without limitation the
## rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
## sell copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
## 
## * The above copyright notice and this permission notice shall be included in
##   all copies or substantial portions of the Software.
## 
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
## IN THE SOFTWARE.
##############################################################################

# Purpose: Convert old-style (YASK v2) DSL code to use only the published
# YASK compiler APIs.

use strict;
use File::Basename;
use File::Path;
use lib dirname($0)."/lib";
use lib dirname($0)."/../lib";

use File::Which;
use Text::ParseWords;
use FileHandle;
use CmdLine;

$| = 1;                         # autoflush.

# Globals.
my %OPT;                        # cmd-line options.

sub convert($) {
  my $fname = shift;

  open INF, "<$fname" or die("error: cannot open '$fname'\n");
  warn "Converting '$fname'...\n";

  # Read old file and save conversion in a string.
  my $result;
  my $lineno = 0;
  my $class_name;
  my $list_var;
  while (<INF>) {
    $lineno++;
    chomp;

    # Capture class name.
    if (/class\s+([_\w]+)/) {
      $class_name = $1;
    }

    # Capture stencilList parameter name.
    if (/StencilList\s*&\s*([_\w]+)/) {
      $list_var = $1;
    }

    # Register solution.
    if (/REGISTER_STENCIL[(](.*)[)]/) {
      my $cname = $1;

      $result .=
        "// Create an object of type '$cname',\n".
        "// making it available in the YASK compiler utility via the\n".
        "// '-stencil' commmand-line option or the 'stencil=' build option.\n".
        "static $cname ${cname}_instance;\n";
    }

    # Include file.
    elsif (/[#]include.*Soln[.]hpp/) {
      $result .= "// YASK stencil solution(s) in this file will be integrated into the YASK compiler utility.\n".
        "#include \"yask_compiler_utility_api.hpp\"\n";
    }

    # For other code, make substitutions and append changes.
    else {

      # Ctor: remove StencilList parameter.
      s/$class_name\s*[(]\s*StencilList\s*&\s*$list_var\s*,\s*/$class_name(/
        if defined $class_name;
      s/$list_var\s*,\s*//g
        if defined $list_var;
    
      # Index creation.
      s/MAKE_STEP_INDEX[(]([^)]+)[)]/yc_index_node_ptr $1 = _node_factory.new_step_index("$1")/g;
      s/MAKE_DOMAIN_INDEX[(]([^)]+)[)]/yc_index_node_ptr $1 = _node_factory.new_domain_index("$1")/g;
      s/MAKE_MISC_INDEX[(]([^)]+)[)]/yc_index_node_ptr $1 = _node_factory.new_misc_index("$1")/g;

      # Grid creation.
      s/MAKE_GRID[(]([^,]+),\s*([^)]+)[)]/auto $1 = yc_grid_var("$1", get_solution(), { $2 })/g;
      s/MAKE_ARRAY[(]([^,]+),\s*([^)]+)[)]/auto $1 = yc_grid_var("$1", get_solution(), { $2 })/g;
      s/MAKE_SCALAR[(]([^,]+)[)]/auto $1 = yc_grid_var("$1", get_solution(), { })/g;
      s/MAKE_SCRATCH_GRID[(]([^,]+),\s*([^)]+)[)]/yc_grid_var $1 = yc_grid_var("$1", get_solution(), { $2 }, true)/g;
      s/MAKE_SCRATCH_ARRAY[(]([^,]+),\s*([^)]+)[)]/yc_grid_var $1 = yc_grid_var("$1", get_solution(), { $2 }, true)/g;
      s/MAKE_SCRATCH_SCALAR[(]([^,]+)[)]/yc_grid_var $1 = yc_grid_var("$1", get_solution(), { }, true)/g;

      # Typenames.
      s/\bStencilBase\b/yc_solution_base/g;
      s/\bStencilRadiusBase\b/yc_solution_with_radius_base/g;
      s/\bGrid\b/yc_grid_var/g;
      s/\bGridIndex\b/yc_number_node_ptr/g;
      s/\bGridValue\b/yc_number_node_ptr/g;
      s/\bCondition\b/yc_bool_node_ptr/g;
      s/\bGridPointPtr\b/yc_grid_point_node_ptr/g;
      s/\bExprPtr\b/yc_expr_node_ptr/g;
      s/\bNumExprPtr\b/yc_number_node_ptr/g;
      s/\bIndexExprPtr\b/yc_index_node_ptr/g;
      s/\bBoolExprPtr\b/yc_bool_node_ptr/g;

      # Other macros.
      s/\b(EQUALS_OPER|IS_EQUIV_TO|IS_EQUIVALENT_TO)\b/EQUALS/g;
      s/\b(IF|IF_OPER)\b/IF_DOMAIN/g;
      s/\b(IF_STEP_OPER)\b/IF_STEP/g;

      # Non-convertable code.
      if (/REGISTER_STENCIL_CONTEXT_EXTENSION|StencilPart/) {
        warn "  Warning: the v2 '$&' construct on line $lineno must be manually edited.\n";
        $result .= "  ## Warning: the v2 '$&' construct cannot be automatically converted.\n".
        "  ## You must manually edit the following line(s).\n";
      }
      
      $result .= "$_\n";
    }
  }
  close INF;

  if ($OPT{in_place}) {
    open OUTF, ">$fname" or die("error: cannot write back to '$fname'\n");

    my $fbak = $fname."~";
    rename "$fname", $fbak or die("error: cannot rename original file to '$fbak'\n");
    warn "  Original code saved in '$fbak'.\n";

    print OUTF $result;
    close OUTF;
    warn "  Converted code written back to '$fname'.\n".
      "  Complete conversion is not guaranteed; please review and test changes.\n";
  }

  # not in-place; print to stdout.
  else {
    print $result;
  }
}

# Parse arguments and emit code.
sub main() {

  my(@KNOBS) =
    (
     # knob,        description,   optional default
     [ "in_place!", "Modify the file(s) in-place. If false, write to stdout.", 1 ],
    );
  my($command_line) = process_command_line(\%OPT, \@KNOBS);
  print "$command_line\n" if $OPT{verbose};

  my $script = basename($0);
  if (!$command_line || $OPT{help} || @ARGV < 1) {
    print "Converts old-style (YASK v2) DSL code to use published YASK compiler APIs.\n",
      "Usage: $script [options] <file-name(s)>\n",
      "Options:\n";
    print_options_help(\@KNOBS);
    exit 1;
  }

  for my $fname (@ARGV) {
    convert($fname);
  }
}

main();
