# Parses the canonical Worker Role sources and projects them onto the native
# Claude/Copilot Markdown and Codex TOML artifacts. Fail-closed: the grammar has
# no quoting, no escaping and no continuation, so anything it cannot represent
# verbatim is rejected rather than silently transformed.

function fail(msg) {
  printf("%s:%d: %s\n", FILENAME, FNR, msg) > "/dev/stderr"
  failed = 1
  exit 65
}

function die(where, msg) {
  printf("%s: %s\n", where, msg) > "/dev/stderr"
  failed = 1
  exit 65
}

function checkline(l) {
  if (l ~ /[ \t]+$/) fail("trailing whitespace is not allowed")
  if (index(l, "\"\"\"") > 0) fail("a line may not contain a TOML \"\"\" delimiter")
  if (l ~ /\\$/) fail("a line may not end with a backslash")
  if (bkind == "description" && l ~ /^[ \t]/) fail("a description line may not start with whitespace")
}

# An entry declares an invariant the role carries. Both runtimes must actually
# receive prose for it, or deleting the cross-runtime phrase locks would be a
# lie: the projection is what guarantees parity now.
function close_group() {
  if (!pending_entry) return
  if (nbc == group_c) fail("the preceding entry produced no Claude prose")
  if (nbx == group_x) fail("the preceding entry produced no Codex prose")
  pending_entry = 0
}

function runtime_ok(rt) {
  return (rt == "claude" || rt == "codex" || rt == "both")
}

function emit(rt, line) {
  if (bkind == "description") {
    if (rt != "codex") dc[++ndc] = line
    if (rt != "claude") dx[++ndx] = line
  } else {
    if (rt != "codex") bc[++nbc] = line
    if (rt != "claude") bx[++nbx] = line
  }
}

BEGIN {
  tools["read"] = "Read"
  sandbox["read"] = "read-only"
  tools["read+search"] = "Read, Grep, Glob"
  sandbox["read+search"] = "read-only"
  tools["read+exec"] = "Bash, Read"
  sandbox["read+exec"] = "workspace-write"
  ndc = 0; ndx = 0; nbc = 0; nbx = 0
  inblock = 0; pending_entry = 0; capability = ""; curid = ""
}

FILENAME == sharedfile {
  if (inblock) {
    if ($0 == "END") { inblock = 0; next }
    next
  }
  if ($0 == "" || substr($0, 1, 1) == "#") next
  if ($1 == "id") {
    if (NF != 2) fail("id takes exactly one argument")
    curid = $2
    if (curid in seen) fail("duplicate id " curid)
    if (curid !~ /^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$/) fail("id must match [a-z0-9.-]: " curid)
    seen[curid] = 1
    next
  }
  if ($1 == "applies") {
    if (curid == "") fail("applies before any id")
    if (NF < 2) fail("applies needs at least one role")
    hasapplies[curid] = 1
    next
  }
  if ($1 == "class") {
    if (curid == "") fail("class before any id")
    if (NF != 2) fail("class takes exactly one argument")
    if ($2 != "shared" && $2 != "runtime" && $2 != "drift") fail("unknown class " $2)
    cls[curid] = $2
    next
  }
  if ($1 == "intent") {
    if (curid == "") fail("intent before any id")
    if (NF != 1) fail("intent takes no arguments")
    hasintent[curid] = 1
    inblock = 1
    bkind = "intent"
    next
  }
  fail("unknown directive: " $1)
}

FILENAME != sharedfile {
  if (inblock) {
    if ($0 == "END") {
      inblock = 0
      if (bkind == "literal" && bcount > 2) fail("a literal block may hold at most 2 lines")
      next
    }
    checkline($0)
    emit(brt, $0)
    bcount++
    next
  }
  if ($0 == "" || substr($0, 1, 1) == "#") next
  if ($1 == "capability") {
    if (NF != 2) fail("capability takes exactly one argument")
    if (!($2 in tools)) fail("unknown capability " $2)
    if (capability != "") fail("capability declared twice")
    capability = $2
    next
  }
  if ($1 == "description") {
    if (NF != 2 || !runtime_ok($2)) fail("description needs a runtime: claude, codex, or both")
    bkind = "description"; brt = $2; inblock = 1; bcount = 0
    next
  }
  if ($1 == "entry") {
    if (NF < 2) fail("entry needs at least one id")
    for (i = 2; i <= NF; i++) {
      if (!($i in seen)) fail("unknown id " $i "; declare it in shared.role")
      uses[$i] = 1
    }
    close_group()
    pending_entry = 1
    group_c = nbc
    group_x = nbx
    next
  }
  if ($1 == "prose") {
    if (NF != 2 || !runtime_ok($2)) fail("prose needs a runtime: claude, codex, or both")
    if (!pending_entry) fail("prose must follow an entry; use literal for text carrying no invariant")
    bkind = "prose"; brt = $2; inblock = 1; bcount = 0
    next
  }
  if ($1 == "literal") {
    if (NF != 2 || !runtime_ok($2)) fail("literal needs a runtime: claude, codex, or both")
    close_group()
    bkind = "literal"; brt = $2; inblock = 1; bcount = 0
    next
  }
  if ($1 == "blank") {
    if (NF != 2 || !runtime_ok($2)) fail("blank needs a runtime: claude, codex, or both")
    close_group()
    bkind = "prose"; emit($2, "")
    next
  }
  fail("unknown directive: " $1)
}

END {
  if (failed) exit 65
  if (inblock) die(FILENAME, "unterminated block; add END")
  if (pending_entry && (nbc == group_c || nbx == group_x))
    die(FILENAME, "the final entry does not produce prose for both runtimes")
  for (id in seen) {
    if (!(id in cls)) die(sharedfile, "id " id " has no class")
    if (!(id in hasapplies)) die(sharedfile, "id " id " has no applies")
    if (!(id in hasintent)) die(sharedfile, "id " id " has no intent")
  }
  if (!("role.description" in seen)) die(sharedfile, "id role.description must be declared")
  if (capability == "") die(FILENAME, "no capability declared")
  if (ndc == 0) die(FILENAME, "no Claude description")
  if (ndx != 1) die(FILENAME, "the Codex description must be exactly one line")
  if (index(dx[1], "\"") > 0 || index(dx[1], "\\") > 0)
    die(FILENAME, "the Codex description may not contain a quote or a backslash")
  if (nbc == 0) die(FILENAME, "empty Claude body")
  if (nbx == 0) die(FILENAME, "empty Codex body")
  uses["role.description"] = 1

  printf("---\n") > outmd
  printf("name: %s\n", role) > outmd
  printf("description: >-\n") > outmd
  for (i = 1; i <= ndc; i++) printf("  %s\n", dc[i]) > outmd
  printf("tools: %s\n", tools[capability]) > outmd
  printf("---\n\n") > outmd
  for (i = 1; i <= nbc; i++) printf("%s\n", bc[i]) > outmd
  close(outmd)

  printf("name = \"%s\"\n", role) > outtoml
  printf("description = \"%s\"\n", dx[1]) > outtoml
  printf("sandbox_mode = \"%s\"\n", sandbox[capability]) > outtoml
  printf("\n") > outtoml
  printf("developer_instructions = \"\"\"\n") > outtoml
  for (i = 1; i <= nbx; i++) printf("%s\n", bx[i]) > outtoml
  printf("\"\"\"\n") > outtoml
  close(outtoml)

  for (id in uses) printf("%s\n", id) > outuses
  close(outuses)
}
