$! VMS_INSTALLCHECK.COM <tree-dir-name> <m4-tree-dir-name> - install the BISON
$! kit (and the M4 kit it requires, from the node's vms-m4 tree, if M4 is not
$! installed), verify it, generate and run a parser with it, then remove what
$! it installed.  Changes the system while it runs (PCSI database,
$! SYS$COMMON:[BISON] and [M4], BISON$ROOT, M4$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ here = f$environment("DEFAULT")
$ tree = here - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ m4kitdir = here - "]" + "." + p2 + ".KIT_''arch']"
$ m4_installed_here = 0
$ if f$trnlnm("M4$ROOT") .eqs. ""
$ then
$   write sys$output "=== INSTALL M4 (prerequisite) from ", m4kitdir
$   product install M4 /producer=ISSINOHO /base_system='base' /source='m4kitdir' /options=noconfirm /log
$   write sys$output "=== M4 install status ", $status
$   m4_installed_here = 1
$ endif
$ write sys$output "=== INSTALL from ", kitdir
$ product install BISON /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product BISON /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:BISON$STARTUP.COM"), "]"
$ show logical BISON$ROOT
$ write sys$output "data file: [", f$search("BISON$ROOT:[DATA.M4SUGAR]M4SUGAR.M4"), "]"
$ write sys$output "c++ skeleton: [", f$search("BISON$ROOT:[DATA.SKELETONS]C^+^+.M4"), "]"
$ write sys$output "=== BISON FROM THE INSTALLED KIT"
$ @BISON$ROOT:[000000]BISON$SETUP.COM
$ set process/parse_style=extended
$ if f$search("BIC.DIR") .eqs. "" then create/directory [.BIC]
$ set default [.BIC]
$ define/user sys$output out.txt
$ bison --version
$ search/nooutput out.txt "GNU Bison"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "BISON_VERSION: PASS"
$ if sev .ne. 1 then write sys$output "BISON_VERSION: FAIL"
$ copy/nolog BISON$ROOT:[DOC]CALC.Y []
$ bison --defines -o calc.c calc.y
$ sev = $severity
$ if sev .eq. 1 .and. f$search("calc.c") .nes. "" then write sys$output "BISON_GENERATE: PASS"
$ if sev .ne. 1 .or. f$search("calc.c") .eqs. "" then write sys$output "BISON_GENERATE: FAIL"
$ cc/nolist calc.c
$ link/nomap calc
$ calc = "$" + f$parse("calc.exe")
$ define/user sys$output out.txt
$ calc "2+3*4"
$ type out.txt
$ search/nooutput/exact out.txt "14"
$ sev = $severity
$ if sev .eq. 1 then write sys$output "BISON_PARSER_RUNS: PASS"
$ if sev .ne. 1 then write sys$output "BISON_PARSER_RUNS: FAIL"
$! A failed run has error severity under DCL (capture $STATUS once: any
$! assignment resets $STATUS and $SEVERITY)
$ define/user sys$error nla0:
$ bison nonexistent.y
$ st = $status
$ sev = st .and. 7
$ write sys$output "failed run status ", st, " severity ", sev
$ if sev .eq. 2 .or. sev .eq. 4 then write sys$output "BISON_ERROR_SEVERITY: PASS"
$ if sev .ne. 2 .and. sev .ne. 4 then write sys$output "BISON_ERROR_SEVERITY: FAIL"
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed BIC.DIR
$ delete/nolog BIC.DIR;
$ delete/symbol/global bison
$ write sys$output "=== REMOVE"
$ product remove BISON /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "BISON$ROOT after removal: [", f$trnlnm("BISON$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[BISON...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:BISON$STARTUP.COM"), "]"
$ if m4_installed_here
$ then
$   product remove M4 /producer=ISSINOHO /options=noconfirm /log
$   write sys$output "M4$ROOT after removal: [", f$trnlnm("M4$ROOT"), "]"
$ endif
$ product show product BISON /producer=ISSINOHO
