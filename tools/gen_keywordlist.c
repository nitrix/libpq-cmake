/*
 * gen_keywordlist — C port of upstream src/tools/gen_keywordlist.pl
 * (plus the entirety of src/tools/PerfectHash.pm).
 *
 * Reads a `kwlist.h`-style header containing lines like
 *     PG_KEYWORD("abort", ABORT_P, UNRESERVED_KEYWORD, BARE_LABEL)
 * and emits the matching `kwlist_d.h` containing a `ScanKeywordList`
 * struct plus a minimal-perfect-hash lookup function whose output
 * matches upstream `kwlist_d.h` byte-for-byte.
 *
 * The perfect-hash construction follows Czech/Havas/Majewski
 * (Information Processing Letters 43:5, October 1992) — the same
 * algorithm the original Perl implementation uses, with the same
 * deterministic seed-search order so the generated file is stable.
 *
 * Build tool — no link-time dependency on libpq.
 *
 * Usage:
 *     gen_keywordlist [--varname NAME] [--extern] [--no-case-fold]
 *                     --output DIR  input.h
 */
#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Dynamic arrays                                                     */
/* ------------------------------------------------------------------ */

typedef struct {
    char  **data;
    size_t  len;
    size_t  cap;
} StrVec;

static void strvec_push(StrVec *v, const char *s)
{
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 64;
        v->data = realloc(v->data, v->cap * sizeof *v->data);
        if (!v->data) { perror("realloc"); exit(1); }
    }
    v->data[v->len++] = strdup(s);
    if (!v->data[v->len - 1]) { perror("strdup"); exit(1); }
}

typedef struct {
    int    *data;
    size_t  len;
    size_t  cap;
} IntVec;

static void intvec_push(IntVec *v, int x)
{
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 16;
        v->data = realloc(v->data, v->cap * sizeof *v->data);
        if (!v->data) { perror("realloc"); exit(1); }
    }
    v->data[v->len++] = x;
}

static void intvec_remove(IntVec *v, int x)
{
    for (size_t i = 0; i < v->len; i++) {
        if (v->data[i] == x) {
            v->data[i] = v->data[--v->len];
            return;
        }
    }
}

/* ------------------------------------------------------------------ */
/* Hash construction                                                  */
/* ------------------------------------------------------------------ */

static uint32_t
calc_hash(const char *key, uint32_t mult, uint32_t seed, bool case_fold)
{
    uint32_t r = seed;
    for (const unsigned char *p = (const unsigned char *)key; *p; p++) {
        uint32_t c = *p;
        if (case_fold) c |= 0x20;
        r = r * mult + c;
    }
    return r;
}

typedef struct { uint32_t left, right; } Edge;

/*
 * Try one hash-parameter quadruple. On success, fills *out_hashtab with
 * `*out_nverts` int32 mapping entries plus the chosen narrowest element
 * type (`int8` / `int16` / `int32`) and unused-flag value.
 *
 * Returns true if the parameters produced an acyclic graph, false to
 * try the next parameter set.
 */
static bool
construct_hash_table(char **keys, size_t nkeys, bool case_fold,
                     uint32_t mult1, uint32_t mult2,
                     uint32_t seed1,  uint32_t seed2,
                     int32_t **out_hashtab, size_t *out_nverts,
                     const char **out_elemtype, int32_t *out_unused_flag)
{
    size_t nedges = nkeys;
    size_t nverts = 2 * nedges + 1;
    while (nverts % mult1 == 0 || nverts % mult2 == 0) nverts++;

    Edge *E = calloc(nedges, sizeof *E);
    IntVec *V = calloc(nverts, sizeof *V);
    if (!E || !V) { perror("calloc"); exit(1); }

    bool ok = true;
    for (size_t i = 0; i < nedges; i++) {
        uint32_t h1 = calc_hash(keys[i], mult1, seed1, case_fold) % nverts;
        uint32_t h2 = calc_hash(keys[i], mult2, seed2, case_fold) % nverts;
        if (h1 == h2) { ok = false; break; }
        E[i].left  = h1;
        E[i].right = h2;
        intvec_push(&V[h1], (int)i);
        intvec_push(&V[h2], (int)i);
    }

    int *output_order = NULL;
    size_t order_len = 0;
    bool *visited = NULL;
    int32_t *hashtab = NULL;

    if (!ok) goto cleanup;

    /* Peel degree-1 vertices until graph is empty or stuck. */
    output_order = malloc(nedges * sizeof *output_order);
    if (!output_order) { perror("malloc"); exit(1); }

    for (size_t startv = 0; startv < nverts; startv++) {
        size_t v = startv;
        while (V[v].len == 1) {
            int e = V[v].data[0];
            V[v].len = 0;

            size_t v2 = (E[e].left == v) ? E[e].right : E[e].left;
            intvec_remove(&V[v2], e);

            /* unshift: insert at front -> we'll reverse later. */
            output_order[order_len++] = e;
            v = v2;
        }
    }

    if (order_len != nedges) { ok = false; goto cleanup; }

    /* Reverse: we appended in removal order, original Perl unshifts. */
    for (size_t i = 0, j = order_len - 1; i < j; i++, j--) {
        int t = output_order[i];
        output_order[i] = output_order[j];
        output_order[j] = t;
    }

    hashtab = calloc(nverts, sizeof *hashtab);
    visited = calloc(nverts, sizeof *visited);
    if (!hashtab || !visited) { perror("calloc"); exit(1); }

    for (size_t i = 0; i < order_len; i++) {
        int e = output_order[i];
        uint32_t l = E[e].left, r = E[e].right;
        if (!visited[l]) {
            hashtab[l] = e - hashtab[r];
        } else {
            if (visited[r]) {
                fprintf(stderr, "doubly used hashtab entry\n");
                exit(1);
            }
            hashtab[r] = e - hashtab[l];
        }
        visited[l] = visited[r] = true;
    }

    int32_t hmin = (int32_t)nedges, hmax = 0;
    for (size_t v = 0; v < nverts; v++) {
        if (hashtab[v] < hmin) hmin = hashtab[v];
        if (hashtab[v] > hmax) hmax = hashtab[v];
    }

    const char *elemtype;
    int32_t unused_flag;
    if (hmin >= -0x7F && hmax <= 0x7F && hmin + 0x7F >= (int32_t)nedges) {
        elemtype = "int8"; unused_flag = 0x7F;
    } else if (hmin >= -0x7FFF && hmax <= 0x7FFF && hmin + 0x7FFF >= (int32_t)nedges) {
        elemtype = "int16"; unused_flag = 0x7FFF;
    } else if (hmin >= -0x7FFFFFFF && hmax <= 0x7FFFFFFF &&
               hmin + 0x3FFFFFFF >= (int32_t)nedges) {
        elemtype = "int32"; unused_flag = 0x3FFFFFFF;
    } else {
        fprintf(stderr, "hash table values too wide\n");
        exit(1);
    }

    for (size_t v = 0; v < nverts; v++)
        if (!visited[v]) hashtab[v] = unused_flag;

    *out_hashtab     = hashtab;
    *out_nverts      = nverts;
    *out_elemtype    = elemtype;
    *out_unused_flag = unused_flag;
    hashtab = NULL;  /* hand ownership to caller */

cleanup:
    for (size_t v = 0; v < nverts; v++) free(V[v].data);
    free(V);
    free(E);
    free(output_order);
    free(visited);
    free(hashtab);
    return ok;
}

/* ------------------------------------------------------------------ */
/* Input parsing                                                      */
/* ------------------------------------------------------------------ */

/* Extracts `KW` from a line beginning (after leading whitespace) with
 * `PG_KEYWORD("KW"`, returning a newly malloc'd lower-case copy or NULL
 * if the line doesn't match.
 */
static char *
parse_pg_keyword(const char *line)
{
    while (*line == ' ' || *line == '\t') line++;
    static const char prefix[] = "PG_KEYWORD(\"";
    if (strncmp(line, prefix, sizeof prefix - 1) != 0) return NULL;
    line += sizeof prefix - 1;
    const char *end = strchr(line, '"');
    if (!end) return NULL;
    size_t n = (size_t)(end - line);
    char *kw = malloc(n + 1);
    if (!kw) { perror("malloc"); exit(1); }
    memcpy(kw, line, n);
    kw[n] = '\0';
    return kw;
}

/* ------------------------------------------------------------------ */
/* Output                                                             */
/* ------------------------------------------------------------------ */

static void
emit_hash_function(FILE *out, const char *funcname,
                   const int32_t *hashtab, size_t nverts,
                   const char *elemtype, uint32_t mult1, uint32_t mult2,
                   uint32_t seed1, uint32_t seed2, bool case_fold)
{
    fprintf(out, "int\n%s(const void *key, size_t keylen)\n{\n", funcname);
    fprintf(out, "\tstatic const %s h[%zu] = {\n\t\t", elemtype, nverts);
    for (size_t i = 0; i < nverts; i++) {
        char num[16];
        int len = snprintf(num, sizeof num, "%d", hashtab[i]);
        fprintf(out, "%s", num);
        if (i == nverts - 1) break;
        if (i % 8 == 7) fprintf(out, ",\n\t\t");
        else            fprintf(out, ",%*s", 6 - len, "");
    }
    if (nverts % 8 != 0) fprintf(out, "\n");
    fprintf(out, "\t};\n\n");
    fprintf(out, "\tconst unsigned char *k = (const unsigned char *) key;\n");
    fprintf(out, "\tuint32\t\ta = %u;\n",   seed1);
    fprintf(out, "\tuint32\t\tb = %u;\n\n", seed2);
    fprintf(out, "\twhile (keylen--)\n\t{\n");
    fprintf(out, "\t\tunsigned char c = *k++%s;\n\n",
            case_fold ? " | 0x20" : "");
    fprintf(out, "\t\ta = a * %u + c;\n", mult1);
    fprintf(out, "\t\tb = b * %u + c;\n", mult2);
    fprintf(out, "\t}\n");
    fprintf(out, "\treturn h[a %% %zu] + h[b %% %zu];\n", nverts, nverts);
    fprintf(out, "}\n");
}

static void
uc_inplace(char *s)
{
    for (; *s; s++) *s = (char)toupper((unsigned char)*s);
}

/* ------------------------------------------------------------------ */
/* Driver                                                             */
/* ------------------------------------------------------------------ */

static void usage(const char *prog)
{
    fprintf(stderr,
        "usage: %s [--varname/-v NAME] [--extern/-e] [--no-case-fold]\n"
        "          [--output/-o DIR] input.h\n", prog);
    exit(1);
}

int main(int argc, char **argv)
{
    const char *varname   = "ScanKeywords";
    const char *output_dir = "";
    bool extern_var = false;
    bool case_fold  = true;
    const char *input = NULL;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--extern") || !strcmp(a, "-e")) extern_var = true;
        else if (!strcmp(a, "--no-case-fold"))          case_fold = false;
        else if (!strcmp(a, "--case-fold"))             case_fold = true;
        else if ((!strcmp(a, "--varname") || !strcmp(a, "-v")) && i + 1 < argc)
            varname = argv[++i];
        else if ((!strcmp(a, "--output") || !strcmp(a, "-o")) && i + 1 < argc)
            output_dir = argv[++i];
        else if (!strncmp(a, "--varname=", 10)) varname = a + 10;
        else if (!strncmp(a, "--output=",  9)) output_dir = a + 9;
        else if (a[0] != '-') input = a;
        else usage(argv[0]);
    }
    if (!input) usage(argv[0]);

    /* Build output path: <output_dir>/<basename_without_.h>_d.h */
    const char *slash1 = strrchr(input, '/');
    const char *slash2 = strrchr(input, '\\');
    const char *base   = slash1 > slash2 ? slash1 + 1
                       : slash2          ? slash2 + 1 : input;
    const char *dot    = strrchr(base, '.');
    if (!dot || strcmp(dot, ".h") != 0) {
        fprintf(stderr, "input must be named *.h\n");
        return 1;
    }
    char stem[256];
    size_t n = (size_t)(dot - base);
    if (n + 3 >= sizeof stem) { fprintf(stderr, "name too long\n"); return 1; }
    memcpy(stem, base, n);
    snprintf(stem + n, sizeof stem - n, "_d");

    char outpath[1024];
    int slen = (int)strlen(output_dir);
    bool need_slash = slen > 0 &&
                      output_dir[slen - 1] != '/' &&
                      output_dir[slen - 1] != '\\';
    snprintf(outpath, sizeof outpath, "%s%s%s.h",
             output_dir, need_slash ? "/" : "", stem);

    /* Parse keywords. */
    FILE *in = fopen(input, "r");
    if (!in) { perror(input); return 1; }
    StrVec keys = {0};
    char line[2048];
    while (fgets(line, sizeof line, in)) {
        char *kw = parse_pg_keyword(line);
        if (!kw) continue;
        if (case_fold) {
            for (char *p = kw; *p; p++) {
                if (*p >= 'A' && *p <= 'Z') {
                    fprintf(stderr, "keyword '%s' is not lower-case\n", kw);
                    return 1;
                }
            }
        }
        strvec_push(&keys, kw);
        free(kw);
    }
    fclose(in);

    /* Verify ASCII order (matches upstream's cheap dedup check). */
    for (size_t i = 0; i + 1 < keys.len; i++) {
        if (strcmp(keys.data[i], keys.data[i + 1]) >= 0) {
            fprintf(stderr, "keyword '%s' is out of order\n", keys.data[i + 1]);
            return 1;
        }
    }

    /* Search for working hash parameters. */
    const uint32_t mult1 = 257;
    const uint32_t mult2_candidates[] = { 17, 31, 127, 8191 };
    int32_t *hashtab = NULL;
    size_t nverts = 0;
    const char *elemtype = NULL;
    int32_t unused_flag = 0;
    uint32_t mult2 = 0, seed1 = 0, seed2 = 0;
    bool found = false;
    for (seed1 = 0; seed1 < 10 && !found; seed1++)
        for (seed2 = 0; seed2 < 10 && !found; seed2++)
            for (size_t m = 0; m < 4 && !found; m++) {
                mult2 = mult2_candidates[m];
                if (construct_hash_table(keys.data, keys.len, case_fold,
                                         mult1, mult2, seed1, seed2,
                                         &hashtab, &nverts, &elemtype,
                                         &unused_flag))
                    found = true;
            }
    if (!found) { fprintf(stderr, "failed to generate perfect hash\n"); return 1; }
    seed1--; seed2--; /* the for-loops over-increment by 1 before breaking */

    /* Emit output header. */
    FILE *out = fopen(outpath, "w");
    if (!out) { perror(outpath); return 1; }

    char stem_uc[256];
    snprintf(stem_uc, sizeof stem_uc, "%s", stem);
    uc_inplace(stem_uc);

    fprintf(out,
        "/*-------------------------------------------------------------------------\n"
        " *\n"
        " * %s.h\n"
        " *    List of keywords represented as a ScanKeywordList.\n"
        " *\n"
        " * Portions Copyright (c) 1996-2024, PostgreSQL Global Development Group\n"
        " * Portions Copyright (c) 1994, Regents of the University of California\n"
        " *\n"
        " * NOTES\n"
        " *  ******************************\n"
        " *  *** DO NOT EDIT THIS FILE! ***\n"
        " *  ******************************\n"
        " *\n"
        " *  It has been GENERATED by libpq-cmake's tools/gen_keywordlist.c\n"
        " *\n"
        " *-------------------------------------------------------------------------\n"
        " */\n\n"
        "#ifndef %s_H\n"
        "#define %s_H\n\n"
        "#include \"common/kwlookup.h\"\n\n",
        stem, stem_uc, stem_uc);

    /* String table. */
    fprintf(out, "static const char %s_kw_string[] =\n\t\"", varname);
    for (size_t i = 0; i < keys.len; i++) {
        if (i) fprintf(out, "\\0\"\n\t\"");
        fputs(keys.data[i], out);
    }
    fprintf(out, "\";\n\n");

    /* Offset table + max length. */
    fprintf(out, "static const uint16 %s_kw_offsets[] = {\n", varname);
    size_t offset = 0;
    size_t max_len = 0;
    for (size_t i = 0; i < keys.len; i++) {
        size_t l = strlen(keys.data[i]);
        fprintf(out, "\t%zu,\n", offset);
        offset += l + 1;
        if (l > max_len) max_len = l;
    }
    fprintf(out, "};\n\n");

    char varname_uc[256];
    snprintf(varname_uc, sizeof varname_uc, "%s", varname);
    uc_inplace(varname_uc);
    fprintf(out, "#define %s_NUM_KEYWORDS %zu\n\n", varname_uc, keys.len);

    /* Hash function. */
    char funcname[300];
    snprintf(funcname, sizeof funcname, "%s_hash_func", varname);
    fprintf(out, "static ");
    emit_hash_function(out, funcname, hashtab, nverts, elemtype,
                       mult1, mult2, seed1, seed2, case_fold);
    fprintf(out, "\n");

    /* ScanKeywordList variable. */
    if (!extern_var) fprintf(out, "static ");
    fprintf(out,
        "const ScanKeywordList %s = {\n"
        "\t%s_kw_string,\n"
        "\t%s_kw_offsets,\n"
        "\t%s,\n"
        "\t%s_NUM_KEYWORDS,\n"
        "\t%zu\n"
        "};\n\n",
        varname, varname, varname, funcname, varname_uc, max_len);
    fprintf(out, "#endif\t\t\t\t\t\t\t/* %s_H */\n", stem_uc);

    if (fclose(out)) { perror(outpath); return 1; }
    free(hashtab);
    for (size_t i = 0; i < keys.len; i++) free(keys.data[i]);
    free(keys.data);
    return 0;
}
