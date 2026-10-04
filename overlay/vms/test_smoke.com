$! TEST_SMOKE.COM - smoke test for the built bison ([.BIN_<arch>]BISON.EXE)
$!
$! Usage:  @[.VMS]TEST_SMOKE [m4-image]
$! P1: the GNU m4 image bison runs (default M4$ROOT:[BIN]M4.EXE, the M4
$!     kit); tools/test.sh passes the node's vms-m4 build.  BISON$ROOT is
$!     pointed at this tree, so bison finds its data files through its
$!     compiled-in default /BISON$ROOT/data.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ bison = "$" + f$parse("[.BIN_''arch']BISON.EXE")
$ top = f$parse("[]",,,"DEVICE","NO_CONCEAL") + -
        (f$parse("[]",,,"DIRECTORY","NO_CONCEAL") - "][" - "]") + ".]"
$ define/process/translation_attributes=concealed BISON$ROOT 'top'
$ if p1 .nes. "" then define/process M4 'p1'
$ pass = 0
$ fail = 0
$ if f$search("SMOKE.DIR") .eqs. "" then create/directory [.SMOKE]
$ copy/nolog [.VMS]CALC.Y [.SMOKE]
$ set default [.SMOKE]
$ set process/parse_style=extended
$!
$! 1. version
$ define/user sys$output out.txt
$ bison --version
$ search/nooutput out.txt "GNU Bison) 3.8"
$ sev = $severity
$ name = "version"
$ gosub check_success
$!
$! 2. generate a parser (bison runs m4) with its header
$ bison --defines -o calc.c calc.y
$ sev = $severity
$ if sev .eq. 1 .and. f$search("calc.c") .eqs. "" then sev = 2
$ name = "generate calc.c from calc.y (runs m4)"
$ gosub check_success
$ search/nooutput calc.c "yyparse"
$ sev = $severity
$ name = "calc.c contains yyparse"
$ gosub check_success
$ search/nooutput calc.h "YYSTYPE"
$ sev = $severity
$ name = "--defines writes calc.h"
$ gosub check_success
$!
$! 3. the generated parser compiles, links and works
$ cc/nolist/object=calc.obj calc.c
$ link/nomap/executable=calc.exe calc.obj
$ calc = "$" + f$parse("calc.exe")
$ define/user sys$output out.txt
$ calc "2+3*4"
$ search/nooutput/exact out.txt "14"
$ sev = $severity
$ name = "generated parser compiles and computes 2+3*4 = 14"
$ gosub check_success
$!
$! 4. a grammar error gives an error status
$ create bad.y
%%
start: 'a' %bogus ;
$ define/user sys$error nla0:
$ bison -o bad.c bad.y
$ sev = $severity
$ name = "grammar error gives an error status"
$ gosub check_failure
$!
$! 5. a missing m4 gives an error status, not a hang
$ define/process M4 "SYS$SCRATCH:NO_SUCH_M4.EXE"
$ define/user sys$error nla0:
$ bison -o calc2.c calc.y
$ sev = $severity
$ if p1 .nes. "" then define/process M4 'p1'
$ if p1 .eqs. "" then deassign/process M4
$ name = "missing m4 gives an error status"
$ gosub check_failure
$!
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed"
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed SMOKE.DIR
$ delete/nolog SMOKE.DIR;
$ deassign/process BISON$ROOT
$ if f$trnlnm("M4", "LNM$PROCESS") .nes. "" then deassign/process M4
$ set default 'saved_default'
$ if fail .eq. 0 then exit 1
$ exit 44
$!
$! The callers save $SEVERITY in sev straight after the command: any
$! assignment (name = ...) resets it.
$check_success:
$ if sev .eq. 1
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ")"
$   if f$search("out.txt") .nes. ""
$   then
$     write sys$output "   output was:"
$     type out.txt;0
$   endif
$ endif
$ return
$!
$check_failure:
$ if sev .eq. 2 .or. sev .eq. 4
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ", expected an error)"
$ endif
$ return
