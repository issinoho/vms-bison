$! BISON$STARTUP.COM - system startup for GNU Bison on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! BISON$ROOT, pointing at the installed [BISON] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:BISON$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign BISON$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the bison command with
$!     $ @BISON$ROOT:[000000]BISON$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("BISON$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode BISON$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[BISON].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.BISON.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "BISON.]"
$ if root .eqs. dir + "BISON.]"
$ then
$   write sys$error "BISON$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed BISON$ROOT 'dev''root'
$ if f$search("BISON$ROOT:[BIN]BISON.EXE") .eqs. ""
$ then
$   write sys$error "BISON$STARTUP: BISON.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU Bison"
$ say ""
$ say "    At system startup: to define BISON$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:BISON$STARTUP.COM"
$ say "    For each user: to define the bison command, add this line to LOGIN.COM:"
$ say "    $ @BISON$ROOT:[000000]BISON$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE BISON removes the product and deassigns BISON$ROOT."
$ say ""
$ exit 1
