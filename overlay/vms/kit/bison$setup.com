$! BISON$SETUP.COM - define the bison command for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @BISON$ROOT:[000000]BISON$SETUP.COM
$!
$! Upper-case options (-H, -L, -S, -W, ...) need SET PROCESS/PARSE_STYLE=EXTENDED,
$! or double quotes, because traditional DCL parsing changes their case;
$! batch jobs use the traditional style.
$!
$ if f$trnlnm("BISON$ROOT") .eqs. ""
$ then
$   write sys$error "BISON$SETUP: BISON$ROOT is not defined; run BISON$STARTUP.COM first"
$   exit 44
$ endif
$ bison :== $BISON$ROOT:[BIN]BISON.EXE
$ exit 1
