# Cross-file check: a shared id must be applied by exactly the roles that
# reference it, in both directions.

BEGIN {
  n = split(roles, rl, " ")
  while ((getline line < sharedfile) > 0) {
    if (line ~ /^id /) {
      split(line, f, " ")
      id = f[2]
    } else if (line ~ /^applies /) {
      nf = split(line, f, " ")
      for (i = 2; i <= nf; i++) declared[id, f[i]] = 1
    }
  }
  close(sharedfile)
  for (i = 1; i <= n; i++) {
    file = work "/" rl[i] ".uses"
    while ((getline id < file) > 0) used[id, rl[i]] = 1
    close(file)
  }
  bad = 0
  for (k in declared) {
    if (!(k in used)) {
      split(k, p, SUBSEP)
      printf("%s: id %s applies to %s, but that role never references it\n", sharedfile, p[1], p[2]) > "/dev/stderr"
      bad = 1
    }
  }
  for (k in used) {
    if (!(k in declared)) {
      split(k, p, SUBSEP)
      printf("%s: id %s is referenced by %s, but applies does not list it\n", sharedfile, p[1], p[2]) > "/dev/stderr"
      bad = 1
    }
  }
  if (bad) exit 65
}
