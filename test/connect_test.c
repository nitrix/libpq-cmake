/*
 * libpq-cmake smoke test:
 *   1. PQconnectdb against $PG_CONNINFO (or argv[1])
 *   2. SELECT 42, verify the cell value
 *   3. Print libpq version + SSL state, exit 0 on success
 *
 * Exit codes:
 *   0 - success
 *   1 - connection failed
 *   2 - SELECT result mismatch
 *
 * When the connection fails we dump everything we know about the
 * connection (host, hostaddr, port, user, dbname — never the password)
 * and the full PQerrorMessage. stdio is forced to be unbuffered so the
 * diagnostic survives the test exiting under ctest's pipe capture even
 * on Windows / cygwin, where the previous version's `fprintf` was
 * silently lost.
 */
#include <libpq-fe.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void
dump_conn_params(FILE *out, PGconn *conn)
{
    fprintf(out, "  libpq version : %d\n", PQlibVersion());
    fprintf(out, "  PQstatus      : %d\n", (int) PQstatus(conn));
    fprintf(out, "  host          : %s\n",
            PQhost(conn)     ? PQhost(conn)     : "(null)");
    fprintf(out, "  hostaddr      : %s\n",
            PQhostaddr(conn) ? PQhostaddr(conn) : "(null)");
    fprintf(out, "  port          : %s\n",
            PQport(conn)     ? PQport(conn)     : "(null)");
    fprintf(out, "  user          : %s\n",
            PQuser(conn)     ? PQuser(conn)     : "(null)");
    fprintf(out, "  dbname        : %s\n",
            PQdb(conn)       ? PQdb(conn)       : "(null)");
}

int main(int argc, char **argv) {
    /*
     * Force unbuffered stdio. Under ctest the test's stderr is a pipe,
     * which on Windows / cygwin defaults to full-buffered; a small
     * fprintf followed by a non-zero return can otherwise drop the
     * buffer on the floor and `ctest --output-on-failure` ends up
     * showing nothing at all.
     */
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    const char *conninfo = NULL;
    if (argc > 1 && argv[1][0] != '\0') {
        conninfo = argv[1];
    } else {
        conninfo = getenv("PG_CONNINFO");
    }
    if (conninfo == NULL || conninfo[0] == '\0') {
        conninfo = "host=localhost port=5432 user=postgres "
                   "password=postgres dbname=postgres";
    }

    PGconn *conn = PQconnectdb(conninfo);
    if (PQstatus(conn) != CONNECTION_OK) {
        fprintf(stderr, "connect_test: PQconnectdb failed\n");
        dump_conn_params(stderr, conn);
        /* PQerrorMessage is already newline-terminated by libpq. */
        fprintf(stderr, "  error message : %s", PQerrorMessage(conn));
        fflush(stderr);
        PQfinish(conn);
        return 1;
    }

    PGresult *res = PQexec(conn, "SELECT 42");
    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "connect_test: SELECT 42 failed\n");
        dump_conn_params(stderr, conn);
        fprintf(stderr, "  error message : %s", PQerrorMessage(conn));
        fflush(stderr);
        PQclear(res);
        PQfinish(conn);
        return 2;
    }
    const char *cell = PQgetvalue(res, 0, 0);
    if (cell == NULL || strcmp(cell, "42") != 0) {
        fprintf(stderr, "connect_test: SELECT 42 returned '%s'\n",
                cell ? cell : "(null)");
        fflush(stderr);
        PQclear(res);
        PQfinish(conn);
        return 2;
    }

    printf("libpq %d, server '%s', SSL=%s\n",
           PQlibVersion(),
           PQparameterStatus(conn, "server_version"),
           PQsslInUse(conn) ? "yes" : "no");

    PQclear(res);
    PQfinish(conn);
    return 0;
}
