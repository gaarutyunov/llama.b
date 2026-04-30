# Field-by-field tolerant float compare.
#
# Usage: awk -v eps=1e-4 -f fdiff.awk a.txt b.txt
#
# Walks both files in lockstep.  For each pair of lines, splits on white
# space, parses each field as a number, and treats them as equal when
# |a - b| < eps.  Lines that don't parse as floats are compared
# byte-for-byte.  Exits non-zero on the first mismatch and prints a
# diff-style hunk.

function abs(x){ return x < 0 ? -x : x }
function isnum(s){ return s ~ /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$/ }

BEGIN {
    if (eps == "") eps = 1e-4
    if (ARGC != 3) {
        print "usage: awk -v eps=N -f fdiff.awk a b" > "/dev/stderr"
        exit 2
    }
    a = ARGV[1]; b = ARGV[2]
    line = 0
    while (1) {
        ra = (getline la < a)
        rb = (getline lb < b)
        line++
        if (ra <= 0 && rb <= 0) break
        if (ra <= 0) { fail("a ended early at line " line); break }
        if (rb <= 0) { fail("b ended early at line " line); break }
        na = split(la, fa, /[[:space:]]+/)
        nb = split(lb, fb, /[[:space:]]+/)
        if (na != nb) { fail("field count differs at line " line ": " la " vs " lb); break }
        for (i = 1; i <= na; i++) {
            if (isnum(fa[i]) && isnum(fb[i])) {
                if (abs(fa[i] - fb[i]) > eps) {
                    fail(sprintf("line %d field %d: %s vs %s (eps=%g)", line, i, fa[i], fb[i], eps))
                    next
                }
            } else if (fa[i] != fb[i]) {
                fail("line " line " field " i ": " fa[i] " vs " fb[i])
                next
            }
        }
    }
    exit failed
}

function fail(msg) {
    print "fdiff: " msg > "/dev/stderr"
    failed = 1
}
