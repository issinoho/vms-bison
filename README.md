<p align="center">
  <img src="docs/images/banner.svg" alt="GNU Bison for OpenVMS: a DECterm window generating and running a parser, with the GNU head" width="100%">
</p>

# GNU Bison for OpenVMS

[GNU Bison](https://www.gnu.org/software/bison/) (**3.8.2**), the parser generator, built
natively for OpenVMS on **IA64** and **x86-64**, following Bison's own releases. Bison runs
GNU m4 to generate its parsers; it uses [GNU m4 for OpenVMS](https://github.com/issinoho/vms-m4).
It belongs to the same family as [GNU grep](https://github.com/issinoho/vms-grep),
[GNU sed](https://github.com/issinoho/vms-sed), [GNU awk](https://github.com/issinoho/vms-awk),
[GNU Wget](https://github.com/issinoho/vms-wget), [curl](https://github.com/issinoho/vms-curl),
[zlib](https://github.com/issinoho/vms-zlib) and [PCRE2](https://github.com/issinoho/vms-pcre2)
for OpenVMS.

This repository holds **only our changes**: every build starts from the signed GNU release
tarball (Akim Demaille's key, pinned in `keys/`), applies our patches and adds our VMS
files. As for grep, sed, m4 and Wget, Bison's own `configure` runs on a Linux host with
every compile and link test sent to VSI C on the node, and MMS builds the result.

## Status

**Released: [v3.8.2-vms2](https://github.com/issinoho/vms-bison/releases/tag/v3.8.2-vms2).**

| | IA64 (OpenVMS V8.4-2L3, VSI C 7.4) | x86-64 (OpenVMS E9.2-4, VSI C 7.7) |
|---|---|---|
| VSI C configure answers (identical on both) | yes | yes |
| Builds | yes | yes |
| Smoke test: generate a parser (Bison runs m4), compile and run it (`2+3*4` = 14), a redirected `SYS$OUTPUT` gets no extra version, grammar error and missing m4 give error statuses | 8/8 | 8/8 |
| Kit install (with the M4 kit), generate and run a parser from the kit, remove | clean | clean |
| PCSI kit (`BISON`, `V3.8-2E2`, requires `M4`) | `ISSINOHO-I64VMS-BISON-V0308-2E2-1.PCSI` | `ISSINOHO-X86VMS-BISON-V0308-2E2-1.PCSI` |

## Installing the kit

Install the [M4 kit](https://github.com/issinoho/vms-m4/releases/latest) first. Download
the Bison kit for your architecture from the
[latest release](https://github.com/issinoho/vms-bison/releases/latest) and check it against
the release's `SHA256SUMS`. A kit downloaded through a non-VMS system loses its record
format, so restore that first, then install it:

```
$ SET FILE/ATTRIBUTE=(RFM:FIX,LRL:8192,MRS:8192,RAT:NONE) ISSINOHO-*-BISON-V0308-2E2-1.PCSI
$ PRODUCT INSTALL BISON /PRODUCER=ISSINOHO /SOURCE=dev:[dir]
$ @BISON$ROOT:[000000]BISON$SETUP.COM
$ bison --defines -o calc.c BISON$ROOT:[DOC]CALC.Y
```

It installs `[BISON.BIN]BISON.EXE`, the skeletons in `[BISON.DATA...]`, `BISON$SETUP.COM`
(defines the `bison` command), the manual and an example grammar in `[BISON.DOC]`, and
`SYS$STARTUP:BISON$STARTUP.COM`, which defines `BISON$ROOT` (add it to
`SYS$MANAGER:SYSTARTUP_VMS.COM` after the line for `M4$STARTUP.COM`). `PRODUCT REMOVE BISON`
removes it.

## On VMS

- **Running m4.** On Unix Bison talks to m4 through two pipes; OpenVMS has no `fork()`.
  Bison writes all of m4's input before reading any of its output, so here files do the
  work: m4's input and output are temporary files in `SYS$SCRATCH`, and m4 runs in a
  subprocess (`LIB$SPAWN`, patch 0006) whose inherited `SYS$OUTPUT` is dropped, so a
  redirected `SYS$OUTPUT` is left alone. The M4 kit's `M4$ROOT:[BIN]M4.EXE` is the default; the
  `M4` logical name overrides it.
- **Data files.** Bison's skeletons and m4 library are installed in `BISON$ROOT:[DATA...]`;
  the `BISON_PKGDATADIR` logical name overrides the location.
- **Upper-case options in batch jobs.** Under the TRADITIONAL DCL parse style unquoted
  options reach Bison in lower case: `-H` (header) becomes `-h` (help). Use the long options
  (`--defines`), quote the short ones (`"-H"`), or `$ SET PROCESS/PARSE_STYLE=EXTENDED` first.
- **Exit status.** Under DCL a failed run has error severity, so `ON ERROR` works; under a
  GNV shell, `$?` is the exit code as on Unix.

## Patches

| Patch | Purpose |
|---|---|
| 0001 | `lib/malloc/scratch_buffer.h`: avoid the member name `__align`, a VSI C keyword. |
| 0002 | `configure`: look for `struct sched_param` in `<pthread.h>` for host `openvms*`. |
| 0003 | `lib/getprogname.c`: VMS implementation. |
| 0004 | `lib/stdlib.in.h`: route `exit()` through `vms_exit()` for an error-severity status under DCL. |
| 0005 | `lib/*.c`: include `float+.h` as `float_plus.h` (VSI C does not find a name with `+`). |
| 0006 | `src/output.c`, `src/output.h`, `src/files.c`: run m4 without `fork()` (temporary files, a `LIB$SPAWN` subprocess); VMS defaults for the m4 image and the data directory. |
| 0007 | `lib/scratch_buffer.h`: include the generated `scratch_buffer.gl.h` as `scratch_buffer_gl.h`. |
| 0008 | `src/print-xml.c`: `--html` runs `xsltproc` (`%define tool.xsltproc`) in a subprocess, as m4 is run. |

0001-0005 and 0007 are the gnulib fixes of the m4, sed and Wget ports.

## How to build

The build and smoke test need [vms-m4](https://github.com/issinoho/vms-m4) built on the node
(`M4_TREE` in `upstream.conf`). Set up `tools/nodes.conf` as described in
[vms-grep's README](https://github.com/issinoho/vms-grep#2b-build-on-vms-from-the-host-over-ssh).

```sh
git clone https://github.com/issinoho/vms-bison.git
cd vms-bison
tools/vms_configure.sh ia64 # VSI C configure run, about an hour (once per Bison release)
tools/prepare.sh            # fetch + verify, patch, configure with the VSI C answers, MMS lists
tools/build.sh ia64         # upload, then @[.VMS]BUILD on the node (MMS)
tools/test.sh ia64          # smoke test (uses the node's m4 build)
tools/kit.sh ia64           # PCSI kit -> out/kits/
```

## Roadmap

1. Bison's own test suite under GNV, as for grep and sed.
2. Offer patches 0006 and 0008 (running m4 and `xsltproc` without `fork()`) to Bison, and the
   gnulib fixes to gnulib.
3. A port to OpenVMS **Alpha**.

The family of ports, all for IA64 and x86-64, each following its upstream releases:

| Port | Latest release | |
|---|---|---|
| GNU grep — [vms-grep](https://github.com/issinoho/vms-grep) | [v3.12-vms3](https://github.com/issinoho/vms-grep/releases/tag/v3.12-vms3) | with `grep -P` through PCRE2 |
| PCRE2 — [vms-pcre2](https://github.com/issinoho/vms-pcre2) | [v10.49-vms1](https://github.com/issinoho/vms-pcre2/releases/tag/v10.49-vms1) | the regular-expression library |
| GNU sed — [vms-sed](https://github.com/issinoho/vms-sed) | [v4.10-vms1](https://github.com/issinoho/vms-sed/releases/tag/v4.10-vms1) | the stream editor |
| GNU awk (gawk) — [vms-awk](https://github.com/issinoho/vms-awk) | [v5.4.1-vms1](https://github.com/issinoho/vms-awk/releases/tag/v5.4.1-vms1) | built with gawk's own VMS port |
| zlib — [vms-zlib](https://github.com/issinoho/vms-zlib) | [v1.3.2-vms1](https://github.com/issinoho/vms-zlib/releases/tag/v1.3.2-vms1) | the compression library |
| curl — [vms-curl](https://github.com/issinoho/vms-curl) | [v8.22.0-vms1](https://github.com/issinoho/vms-curl/releases/tag/v8.22.0-vms1) | alongside VSI's curl kit, following curl's own releases |
| GNU Wget — [vms-wget](https://github.com/issinoho/vms-wget) | [v1.25.0-vms2](https://github.com/issinoho/vms-wget/releases/tag/v1.25.0-vms2) | the web retriever |
| GNU m4 — [vms-m4](https://github.com/issinoho/vms-m4) | [v1.4.21-vms1](https://github.com/issinoho/vms-m4/releases/tag/v1.4.21-vms1) | the macro processor |
| **GNU Bison** (this port) — [vms-bison](https://github.com/issinoho/vms-bison) | [v3.8.2-vms2](https://github.com/issinoho/vms-bison/releases/tag/v3.8.2-vms2) | runs GNU m4 |
| flex — [vms-flex](https://github.com/issinoho/vms-flex) | [v2.6.4-vms1](https://github.com/issinoho/vms-flex/releases/tag/v2.6.4-vms1) | the scanner generator; runs GNU m4 |
| GNU make — [vms-make](https://github.com/issinoho/vms-make) | [v4.4.1-vms1](https://github.com/issinoho/vms-make/releases/tag/v4.4.1-vms1) | built with make's own VMS port |
| GNU diffutils — [vms-diffutils](https://github.com/issinoho/vms-diffutils) | [v3.12-vms1](https://github.com/issinoho/vms-diffutils/releases/tag/v3.12-vms1) | cmp, diff, diff3, sdiff |
| GNU patch — [vms-patch](https://github.com/issinoho/vms-patch) | [v2.8-vms1](https://github.com/issinoho/vms-patch/releases/tag/v2.8-vms1) | applies diffs |

## Artwork

`docs/images/banner.svg` and `docs/images/icon.svg` were made for this project in the style
of classic DECwindows and VT terminals, like those of its sibling ports. The GNU head is by
Aurelio A. Heckert, used under the terms on <https://www.gnu.org/graphics/heckert_gnu.html>.

## Licence

GNU Bison is free software under the GNU General Public License, version 3 or later; see
`COPYING`. Our patches and VMS files are distributed under the same terms. Parsers Bison
generates may be distributed under the terms of the Bison exception in the generated files.

OpenVMS is a trademark of VMS Software, Inc. This project is not affiliated with VMS
Software, Inc. or with the GNU project.
