#!/usr/bin/env bash
# prepare.sh - build a VMS-ready source tree in staging/<name>-<version>/
#
#   1. fetch + verify the upstream tarball
#   2. extract it, apply patches/series, lay overlay/ over the top
#   3. run the upstream configure on this host, with every platform answer
#      taken from VMS probe results (probed.site) or hand-settled values
#      (vms-manual.site) instead of from Linux
#   4. generate gnulib's headers and config.h, copy them into the tree
#   5. write the MMS source lists and the configuration snapshot
#
# Nothing in staging/ is ever edited by hand: fix things in patches/ or overlay/.
set -euo pipefail

top=$(cd "$(dirname "$0")/.." && pwd)
. "$top/upstream.conf"
name=$UPSTREAM_NAME-$UPSTREAM_VERSION
tarball=$top/cache/$(basename "$UPSTREAM_URL")
stage=$top/staging/$name
hostcfg=$top/cache/hostcfg-$name
cfgdir=$top/overlay/vms/config
snapshot=$top/snapshot
# Configuration answers come from this node's VSI C run; both architectures
# share one CRTL feature set (see docs/vms-environment.md).
PRIMARY_NODE=${PRIMARY_NODE:-ia64}
PRIMARY_TRIPLET=ia64-hp-openvms

step() { echo "prepare: $*"; }
die() { echo "prepare: error: $*" >&2; exit 1; }

"$top/tools/fetch.sh" >/dev/null

# --- 2. extract, patch, overlay -------------------------------------------
step "extracting $name"
rm -rf "$stage"
mkdir -p "$top/staging"
tar -xJf "$tarball" -C "$top/staging"
[ -d "$stage" ] || die "tarball did not unpack to $stage"

while read -r p; do
    case $p in ''|'#'*) continue ;; esac
    step "patch $p"
    patch -d "$stage" -p1 -s --no-backup-if-mismatch -F0 < "$top/patches/$p" ||
        die "patch $p does not apply cleanly"
done < "$top/patches/series"

# overlay/ may only add files; changes to upstream files belong in patches/.
(cd "$top/overlay" && find . -type f) | while read -r f; do
    [ -e "$stage/$f" ] && die "overlay/$f would replace an upstream file; use a patch"
    true
done
cp -a "$top/overlay/." "$stage/"

# --- 3. host configure with VMS answers ----------------------------------
step "configure (host, VMS answers)"
rm -rf "$hostcfg"
mkdir -p "$hostcfg"
site=$hostcfg/vms.site
# Answers: the VSI C configure run (vms_configure.sh) if there is one, else the
# function/header probes; vms-manual.site last so it always wins.
answers=$cfgdir/configure-$PRIMARY_NODE.cache
if [ ! -f "$answers" ]; then
    # First pass of a new release: stage the tree for vms_configure.sh, which
    # writes the answers.  The result is not buildable on VMS yet.
    answers=$hostcfg/no-answers.site; : > "$answers"
    step "WARNING: no $(basename "$cfgdir")/configure-$PRIMARY_NODE.cache yet:" \
         "Linux answers (run tools/vms_configure.sh, then prepare again)"
fi
step "answers from $(basename "$answers")"
python3 "$top/tools/nextheaders_site.py" "$stage/configure" "$cfgdir/crtl_modules.txt" \
    > "$cfgdir/next-headers.site"
cat "$answers" "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$site"
mapfile -t cfgargs < <(grep -v -e '^#' -e '^$' "$cfgdir/configure.args")
# Same --host as vms_configure.sh so configure takes the same code paths.
(cd "$hostcfg" && CONFIG_SITE=$site "$stage/configure" -q -C \
    --build="$("$stage/build-aux/config.guess")" --host=$PRIMARY_TRIPLET CC=gcc "${cfgargs[@]}" \
    > configure.out 2>&1) || { tail -20 "$hostcfg/configure.out"; die "configure failed"; }

# --- 4. generated headers and config.h -------------------------------------
printvar() {  # printvar <dir> <make variable>
    make -s -C "$hostcfg/$1" -f Makefile -f "$top/tools/printvar.mk" "print-$2"
}
# bison has one non-recursive Makefile at the top; its BUILT_SOURCES also
# lists example grammars bison itself generates.  Only gnulib's lib/ headers.
built=$(printvar . BUILT_SOURCES | tr ' ' '\n' | grep '^lib/')
step "generating $(echo $built | wc -w) gnulib headers"
make -s -C "$hostcfg" $built >/dev/null
for h in $built; do
    # Some are shipped in the source tree and not rebuilt.
    [ -f "$hostcfg/$h" ] || { [ -f "$stage/$h" ] && continue; die "no generated $h"; }
    mkdir -p "$stage/$(dirname "$h")"
    cp "$hostcfg/$h" "$stage/$h"
done
cp "$hostcfg/lib/config.h" "$stage/lib/config.h"   # m4: AC_CONFIG_HEADERS([lib/config.h:...])
# VSI C does not find a header with "+" in its name: lib/float+.h is also
# lib/float_plus.h (patch 0008 includes it by that name on VMS).
cp "$stage/lib/float+.h" "$stage/lib/float_plus.h"
# VSI C cannot #include a name with two dots: generated lib/malloc/*.gl.h
# become *_gl.h (patch 0003 includes them by that name on VMS).
for f in "$stage"/lib/malloc/*.gl.h; do
    [ -e "$f" ] || continue
    sed 's|<malloc/\([a-z_-]*\)\.gl\.h>|<malloc/\1_gl.h>|g' "$f" > "${f%.gl.h}_gl.h"
    rm "$f"
done

# --- 5. MMS source lists ---------------------------------------------------
# Objects for libbison (gnulib): automake sources after conditionals, plus
# LIBOBJS (lib/libbison_a-<name>.o); paths relative to lib/.
lib_srcs=$( { printvar . lib_libbison_a_SOURCES
              printvar . lib_libbison_a_LIBADD | tr ' ' '\n' | sed -n 's|^lib/libbison_a-||; s/\.o$/.c/p'
            } | tr ' ' '\n' | grep '\.c$' | sed 's|^lib/||' | sort -u)
# Leave out what cannot work on VMS (overlay/vms/lib-exclude.txt, with reasons).
while read -r pat; do
    case $pat in ''|'#'*) continue ;; esac
    lib_srcs=$(echo "$lib_srcs" | while read -r f; do
        case $(basename "$f") in $pat) ;; *) echo "$f" ;; esac; done)
done < "$top/overlay/vms/lib-exclude.txt"
# Grammars are listed as .y; the release ships the generated .c (parse-gram.c).
src_srcs=$(printvar . src_bison_SOURCES | tr ' ' '\n' | sed 's/\.y$/.c/' | grep '\.c$' |
           sed 's|^src/||' | sort -u)
for f in $src_srcs; do [ -f "$stage/src/$f" ] || die "no src/$f in the release"; done
# Object names must be unique within each object directory (lib objects go to
# their own, so lib/hash.c and src/hash.c can coexist).
for list in "$lib_srcs" "$src_srcs"; do
    dups=$(echo "$list" | xargs -n1 basename | sort | uniq -d)
    [ -z "$dups" ] || die "duplicate object names: $dups"
done

mkdir -p "$stage/vms"
echo "$lib_srcs" > "$hostcfg/lib-sources.txt"
echo "$src_srcs" > "$hostcfg/src-sources.txt"
python3 "$top/tools/gen_mms.py" "$cfgdir/ccflags.txt" "$hostcfg/lib-sources.txt" \
    "$hostcfg/src-sources.txt" "$top/overlay/vms/extra-sources.txt" > "$stage/vms/sources.mms"

# --- PCSI kit inputs (vms/kit/MAKE_KIT.COM builds the kit on each node) ----
step "PCSI kit inputs"
: "${KIT_PRODUCER:=ISSINOHO}"
# Three-part versions (1.25.0): the third part is the PCSI update and our VMS
# patch level the ECO, as in vms-awk and vms-curl, so 3.8.2-vms1 is V3.8-2E1.
IFS=. read -r major minor update _ <<< "$UPSTREAM_VERSION"
pcsiversion="V$major.$minor-${update:-0}E$VMS_PATCH_LEVEL"
kitversion="$UPSTREAM_VERSION-vms$VMS_PATCH_LEVEL"
kit=$stage/vms/kit
subst() {
    sed -e "s/@PRODUCER@/$KIT_PRODUCER/g" -e "s/@BASE@/$1/g" \
        -e "s/@PCSIVERSION@/$pcsiversion/g" -e "s/@VERSION@/$UPSTREAM_VERSION/g" \
        -e "s/@KITVERSION@/$kitversion/g" -e "s/@ARCH@/$2/g"
}
# The data files' directories and files for the product description, in
# VMS form: data/skeletons/c++.m4 -> [BISON.DATA.SKELETONS]c^+^+.m4 (ODS-5
# escapes for "+" and for dots other than the last).
datafiles=$( (cd "$stage/data" && find . -mindepth 1 -type d | sort |
               sed 's|^\./||; s|/|.|g' | tr a-z A-Z |
               sed 's|.*|    directory [BISON.DATA.&] ;|'
             cd "$stage/data" && find . -type f ! -name local.mk | sort | while read -r f; do
                 d=$(dirname "${f#./}"); b=$(basename "$f")
                 dir=BISON.DATA; [ "$d" = . ] || dir="BISON.DATA.$(echo "$d" | tr / . | tr a-z A-Z)"
                 stem=${b%.*}; ext=${b##*.}
                 stem=$(echo "$stem" | sed 's/[+.]/^&/g')
                 echo "    file [$dir]$stem.$ext ;"
             done) )
for base in I64VMS X86VMS; do
    subst $base "" < "$kit/bison.pcsi\$desc_template" |
        awk -v d="$datafiles" '{ if ($0 == "@DATAFILES@") print d; else print }' > "$kit/BISON-$base.PCSI\$DESC"
    subst $base "" < "$kit/bison.pcsi\$text_template" > "$kit/BISON-$base.PCSI\$TEXT"
done
rm -f "$kit/bison.pcsi\$desc_template" "$kit/bison.pcsi\$text_template"
mv "$kit/bison\$startup.com" "$kit/BISON\$STARTUP.COM"
mv "$kit/bison\$setup.com" "$kit/BISON\$SETUP.COM"
subst "" "IA64 and x86-64" < "$kit/readme.vms" > "$kit/README.VMS"; rm -f "$kit/readme.vms"
mkdir -p "$kit/doc"
cp "$stage/COPYING" "$kit/doc/COPYING."
cp "$stage/NEWS" "$kit/doc/NEWS."
cp "$stage/doc/bison.1" "$kit/doc/BISON.1"
cp "$stage/vms/calc.y" "$kit/doc/CALC.Y"
# The manual: doc/bison.info is plain text apart from Info's control lines
# (no makeinfo needed on the host).
sed -e '/^\x1f/d' -e '/^Tag Table:/,$d' -e 's/\x7f[0-9]*//' "$stage/doc/bison.info" |
    tr -d '\000-\010\016-\037\177' > "$kit/doc/BISON.TXT"
printf 'KIT_PRODUCER=%s\nPCSI_VERSION=%s\nKIT_VERSION=%s\n' "$KIT_PRODUCER" "$pcsiversion" \
    "$kitversion" > "$kit/kit.env"

# --- snapshot: the resolved configuration, committed and reviewed ----------
mkdir -p "$snapshot"
cp "$hostcfg/lib/config.h" "$snapshot/config.h"
echo "$lib_srcs" > "$snapshot/lib-sources.txt"
echo "$src_srcs" > "$snapshot/src-sources.txt"
# Every cached answer, and where it came from.
cat "$cfgdir/next-headers.site" "$cfgdir/vms-manual.site" > "$hostcfg/manual.site"
python3 "$top/tools/cfgreport.py" "$hostcfg/config.cache" "$answers" \
    "$hostcfg/manual.site" > "$snapshot/cache-answers.txt"
step "inherited-from-Linux answers: $(grep -c ' host$' "$snapshot/cache-answers.txt" || true)" \
     "(see snapshot/cache-answers.txt)"

step "staged $stage"
if ! git -C "$top" diff --quiet -- snapshot 2>/dev/null; then
    step "snapshot/ changed - review with: git diff -- snapshot"
fi
